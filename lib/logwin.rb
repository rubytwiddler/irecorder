#
#  Log Window
#
class LogWindow < Qt::Widget

    def initialize()
        super

        # create widgets
        @textWidget = KDE::TextEdit.new
        @textWidget.setReadOnly(true)
        clearBtn = KDE::PushButton.new( KDE::Icon.new('edit-clear'), i18n("C&lear") )
        connect(clearBtn, SIGNAL(:clicked)) do
            @textWidget.clear
        end

        # layout
        layout = Qt::VBoxLayout.new
        layout.addWidget(@textWidget)
        layout.addWidgetAtLeft(clearBtn)
        setLayout(layout)
    end

    public
    def write(text)
        puts text
        @textWidget.append(text)
    end

end

class MyLogger
    MISC = 0
    CODE = 1
    DEBUG = 2
    INFO = 3
    WARN = 4
    ERROR = 5
    FATAL = 6
    UNKNOWN = 7

    attr_accessor   :level

    def initialize(logDevice)
        @logdev = logDevice
        @level = 0
    end

    public
    def misc(msg = nil, &block)
        add(MISC, msg, &block)
    end

    def code(msg = nil, &block)
        add(CODE, msg, &block)
    end

    def debug(msg = nil, &block)
        add(DEBUG, msg, &block)
    end

    def info(msg = nil, &block)
        add(INFO, msg, &block)
    end

    def warn(msg = nil, &block)
        add(WARN, msg, &block)
    end

    def error(msg = nil, &block)
        add(ERROR, msg, &block)
    end

    def fatal(msg = nil, &block)
        add(FATAL, msg, &block)
    end


    protected
    def add(lvl, msg, &block)
        return if lvl < @level
        if msg.nil? then
            if block_given? then
                msg = yield
                return if msg.nil?
            else
                return
            end
        end

        msgs = formatMessages(lvl, msg)
        msgs.each do |m|
            @logdev.write(m.chomp)
        end
    end
    alias   log add


    def formatMessages(lvl, msg)
        a = msg2a(msg)
        a.map do |m|
            "%-5s:%s" % [%w(MISC CODE DEBUG INFO WARN ERROR FATAL ANY)[lvl], m]
        end
    end

    def msg2a(msg)
        case msg
        when ::String
            [ msg ]
        when ::Array
            msg
        when ::Exception
            [ msg.class.to_s + ': ' + msg.message ] + [ msg ] +
                (msg.backtrace || []).map do |m| '  from ' + m end
        else
            [ msg.inspect ]
        end
    end
end
