#!/usr/bin/ruby

sleep(rand(10)+4)

cmd = ARGV.join(' ')
puts "cmd : " + cmd
exec(cmd)