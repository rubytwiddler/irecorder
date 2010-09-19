#!/usr/bin/ruby

require 'rbconfig'
require 'rubygems'
require 'rake/gempackagetask'

spec = Gem::Specification.new do |s|
    s.name = "irecorder"
    s.version = "0.0.8"
    s.author = "ruby.twiddler"
    s.email = "ruby.twiddler at gmail.com"
    s.homepage = "http://github.com/rubytwiddler/irecorder/wiki"
    s.summary = "iRecorder is Audio recorder which has KDE GUI looks like BBC iPlayer."
    s.files = FileList["{bin,lib}/**/*"].to_a
    s.files += %w{ README MIT-LICENSE Rakefile resources/bbcstyle.qss }
    s.executables = [ 'irecorder.rb' ]
    s.require_path = "lib"
    s.extensions = [ 'ext/Rakefile' ]
    s.requirements = %w{ korundum4 qtwebkit kio ktexteditor }
    s.add_runtime_dependency( 'nokogiri', '>= 1.4.0' )
    s.description = <<-EOF
iRecorder is Audio recorder which has KDE GUI looks like BBC iPlayer.
You can browse BBC Radio programmes and click to download stream file.
files will be converted to mp3 files automatically.
irecorder allow to play without any other browser or play on your prefered browser.
like mplayer.
irecorder require kdebindings.
    EOF
    s.has_rdoc = false
    s.extra_rdoc_files = ["README"]
end

package = Rake::GemPackageTask.new(spec) do |pkg|
    pkg.need_tar = true
end

desc "install as gem package"
task :installgem => :gem do
    system("gem install -r pkg/" + package.gem_file )
end

desc "install for rpm"
task :install4rpm do
    def installToDir(file, dir, options={})
#         puts "copy #{file} => #{dir}"
        FileUtils.mkdir_p(File.join(dir, File.dirname(file)))
        FileUtils.install(file, File.join(dir, File.dirname(file)), options)
    end

    prefix = ENV['prefix']
    conf = Config::CONFIG
    destDir = conf['sitelibdir'].sub(/#{conf['prefix']}/, prefix)
    destDir = File.join(destDir, spec.name)

    files = FileList["{bin,lib}/**/*"].to_a
    files += %w{ resources/bbcstyle.qss }
    files.each do |f|
        # install files.
        installToDir(f, destDir)
    end

    installToDir('bin/irecorder', prefix, :mode => 0755)
end


resouce_files = [ 'resources/irecorder.qrc' ] + FileList['resources/images/*.png']
desc "package resources"
file 'lib/irecorder_resource.rb' => resouce_files  do
    open("lib/irecorder_resource.rb", 'w') do |w|
        open("|rbrcc resources/irecorder.qrc") do |f|
            f.each_line do |l|
                l.sub!(/^(\s*#).*?\/home\/.*?\/irecorder/, "\\1 irecorder")
                w.write(l)
            end
        end
    end
end

task :resource => 'lib/irecorder_resource.rb'