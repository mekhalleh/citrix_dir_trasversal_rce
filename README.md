# citrix_dir_trasversal_rce

An issue was discovered in Citrix Application Delivery Controller (ADC) and Gateway 10.5, 11.1, 12.0, 12.1, and 13.0. They allow Directory Traversal.

In resume, when the NSPPE receives a request for `GET /vpn/index.html`, it is supposed to send this request to Apache which processes it. However, by making the request `GET /vpn/../vpns/` (which is not sanitized), Apache transforms the route into `GET /vpns/` and processes this last request normally.

This `/vpns/` directory is interesting because it contains Perl code. The script `newbm.pl` creates an array containing information from several parameters, then calls the filewrite function, which writes the content to an XML file on disk.

A malicious attacker can execute arbitrary commands remotely by creating a corrupted xml file who use `Perl Template Toolkit` in part of payload.

This module exploit that ...
