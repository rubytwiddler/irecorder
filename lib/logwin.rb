#
#  Log Window
#
class LogWindow < Qt::Widget

    def initialize()
        super

        # create widgets
        @findLineEdit = KDE::LineEdit.new
        findNextBtn = KDE::PushButton.new(KDE::Icon.new('go-down-search'), i18n('Next'))
        findPrevBtn = KDE::PushButton.new(KDE::Icon.new('go-up-search'), i18n('Previous'))
        @textWidget = KDE::TextEdit.new
        @textWidget.setReadOnly(true)
        clearBtn = KDE::PushButton.new( KDE::Icon.new('edit-clear'), i18n("Clear") )

        level = MyLogger::FATAL
        @labels = %w{ Fatal Error Warn Info Debug Code Misc }.map do |l|
            ClickableLabel.new(l) do |w|
                w.objectName = level.to_s
                level -= 1
                connect(w, SIGNAL(:clicked), self, SLOT(:changeLevel))
            end
        end


        # connect
        connect(clearBtn, SIGNAL(:clicked), @textWidget, SLOT(:clear))
        connect(@findLineEdit, SIGNAL(:returnPressed), self, SLOT(:findNext))
        connect(findNextBtn, SIGNAL(:clicked), self, SLOT(:findNext))
        connect(findPrevBtn, SIGNAL(:clicked), self, SLOT(:findPrevious))


        # layout
        l = Qt::VBoxLayout.new
        l.addWidgets(i18n('Find'), @findLineEdit, findNextBtn, findPrevBtn)
        l.addWidget(@textWidget)
        l.addWidgets(*([clearBtn, nil, @labels, nil].flatten))
        setLayout(l)

        #
        @limitLine = 1000
        @lineCount = 0
    end

    attr_accessor :limitLine


    slots :findNext
    def findNext
        f = @textWidget.find( @findLineEdit.text, 0)
        unless f then
            # initialize @textWidget
            cur = @textWidget.textCursor
            cur.movePosition(Qt::TextCursor::Start)
            @textWidget.setTextCursor(cur)
            @textWidget.find( @findLineEdit.text, 0)
        end
    end

    slots :findPrevious
    def findPrevious
        @textWidget.find( @findLineEdit.text, Qt::TextDocument::FindBackward)
    end

    slots :changeLevel
    def changeLevel
        label = sender
        setLevel(label.objectName.to_i)
    end

    def setLevel(level)
        $log.level = level
        i = MyLogger::FATAL
        @labels.each do |l|
            if i >= level then
                l.text = l.text.upcase
            else
                l.text = l.text.downcase
            end
            i -= 1
        end
    end

    def showEvent(event)
        setLevel($log.level)
    end

    public
    def write(text)
        puts text
        @textWidget.append(text)
        @lineCount += 1
        if @lineCount > @limitLine then
            cur = @textWidget.textCursor
            cur.movePosition(Qt::TextCursor::Start)
            cur.movePosition(Qt::TextCursor::Down, Qt::TextCursor::KeepAnchor, 4)
            cur.removeSelectedText
            cur.movePosition(Qt::TextCursor::End)

            @textWidget.setTextCursor(cur)
            @lineCount -= 4
        end
    end

end


#
#  MyLogger class
#
class MyLogger
    MISC, CODE, DEBUG, INFO, WARN, ERROR, FATAL, UNKNOWN = (0..7).to_a

    attr_accessor   :level

    def initialize(logDevice)
        @logdev = logDevice
        @level = 0
    end

    public
    def setLogDevice(dev)
        @logdev = dev
    end

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
