#!/usr/bin/ruby

require 'rubygems'
require 'rake/gempackagetask'

spec = Gem::Specification.new do |s|
    s.name = "irecorder"
    s.version = "0.0.3"
    s.author = "ruby.twiddler@gmail.com"
    s.email = "ruby.twiddler@gmail.com"
    s.platform = "ruby"
    s.summary = "BBC iPlayer like audio recorder with KDE GUI."
    s.files = FileList["{bin,lib}/**/*"].to_a
    s.files += %w{ MIT-LICENSE Rakefile resources/bbcstyle.qss }
    s.executables = [ 'irecorder.rb' ]
    s.license  = "MIT-LICENSE"
    s.require_path = "lib"
    s.requirements = %w{ korundum4 qtwebkit kio }
    s.add_runtime_dependency( 'nokogiri', '>= 1.4.0' )
    s.description = <<-EOF
BBC iPlayer like audio recorder with KDE GUI.
You can browse BBC Radio programmes and click to download stream file.
files will be converted to mp3 files automatically.
iplayer allow to play without any other browser or on your prefered media player
like mplayer.
    EOF
    s.has_rdoc = true
    s.extra_rdoc_files = ["README"]
end

package = Rake::GemPackageTask.new(spec) do |pkg|
    pkg.need_tar = true
end


task :install => :gem do
    system("gem install -r pkg/" + package.gem_file )
end