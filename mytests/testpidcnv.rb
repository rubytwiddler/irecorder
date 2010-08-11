#!/usr/bin/env ruby

require 'rubygems'
require 'nokogiri'
require 'open-uri'

pid = ARGV[0]

url = "http://www.iplayerconverter.co.uk/pid/#{pid}/default.aspx"
doc = nil
begin
    open(url) do |f|
        doc = Nokogiri::HTML(f)
    end
rescue => exception
    p exception
end

node = doc.at_css("body")
node.css("script").remove

fileUrls = Hash.new
node.content .to_s. split(/,/).each do |a|
    a.gsub!(/[\r\n]+/,'')
    k,v = a.split(/=/, 2)
    puts k,v
    fileUrls[k] = v
end

p fileUrls

