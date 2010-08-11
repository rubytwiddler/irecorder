#!/usr/bin/env ruby

 require 'cgi'

 c = CGI.new

 puts "Content-type: text/html"
 puts
 puts c.user_agent
