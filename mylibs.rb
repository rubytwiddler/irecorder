#
#  My library
#
#   Qt & other miscs

require 'Qt'

#
class Qt::HBoxLayout
    def addWidgets(*w)
        w.each do |e| self.addWidget(e) end
    end
end

class Qt::VBoxLayout
    def addWidgetAtCenter(*w)
        addLayout(
            Qt::HBoxLayout.new do |l|
                l.addStretch
                l.addWidgets(*w)
                l.addStretch
            end
        )
    end

    def addWidgetAtLeft(*w)
        addLayout(
            Qt::HBoxLayout.new do |l|
                l.addStretch
                l.addWidgets(*w)
            end
        )
    end
end


#
class VBoxLayoutWidget < Qt::Widget
    def initialize(parent=nil,  f=nil)
        @layout = Qt::VBoxLayout.new(parent)
        super(parent, f)
        setLayout(@layout)
    end

    def addLayout(l)
        @layout.addLayout(l)
    end

    def addWidget(w)
        @layout.addWidget(w)
    end

    def addWidgetAtLeft(*w)
        @layout.addWidgetAtLeft(*w)
    end

    def addWidgetAtCenter(*w)
        @layout.addWidgetAtCenter(*w)
    end

    def layout
        @layout
    end
end

class HBoxLayoutWidget < Qt::Widget
    def initialize(parent=nil, f=nil)
        @layout = Qt::HBoxLayout.new(parent)
        super(parent, f)
        setLayout(@layout)
    end

    def addLayout(l)
        @layout.addLayout(l)
    end

    def addWidget(w)
        @layout.addWidget(w)
    end

    def layout
        @layout
    end
end

#
class Hash
    alias   old_blaket []
    def [](key)
        unless key.kind_of?(Regexp)
            return old_blaket(key)
        end

        retk, retv = self.find { |k,v| k =~ key }
        retv
    end
end

class Qt::Action
    def setVData(data)
        setData(Qt::Variant.new(data))
    end

    def vData
        self.data.toString
    end
end