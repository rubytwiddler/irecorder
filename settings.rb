#
#    2007 by ruby.twiddler@gmail.com
#
require 'Korundum'
require 'singleton'

class Settings < KDE::ConfigSkeleton
    include Singleton

    def initialize()
        super(__app_name__)

        @valLastFile = Qt::Variant.new( "" )
        @valLastUrl = Qt::Variant.new( "" )

        setCurrentGroup( "State" )
    end

end
