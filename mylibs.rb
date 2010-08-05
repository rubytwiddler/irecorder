#
#  My library
#
#   Qt & other miscs

require 'singleton'
require 'korundum4'

#
class Qt::HBoxLayout
    def addWidgets(*w)
        w.each do |e| self.addWidget(e) end
    end
end

class Qt::VBoxLayout
    def addWidgetWithNilStretch(*w)
        addLayout(
            Qt::HBoxLayout.new do |l|
                w.each do |i|
                    if i
                        l.addWidget(i)
                    else
                        l.addStretch
                    end
                end
            end
        )
    end
    alias :addWidgets :addWidgetWithNilStretch

    def addWidgetAtCenter(*w)
        w.unshift(nil)
        addWidgetWithNilStretch(*w)
    end

    def addWidgetAtRight(*w)
        w.unshift(nil)
        addWidgetWithNilStretch(*w)
    end

    def addWidgetAtLeft(*w)
        w.push(nil)
        addWidgetWithNilStretch(*w)
    end
end


#
class VBoxLayoutWidget < Qt::Widget
    def initialize(parent=nil)
        @layout = Qt::VBoxLayout.new
        super(parent)
        setLayout(@layout)
    end

    def addLayout(l)
        @layout.addLayout(l)
    end

    def addWidget(w)
        @layout.addWidget(w)
    end

    def addWidgetWithNilStretch(*w)
        @layout.addWidgetWithNilStretch(*w)
    end
    alias :addWidgets :addWidgetWithNilStretch

    def addWidgetAtRight(*w)
        @layout.addWidgetAtRight(*w)
    end

    def addWidgetAtCenter(*w)
        @layout.addWidgetAtCenter(*w)
    end

    def layout
        @layout
    end
end

class HBoxLayoutWidget < Qt::Widget
    def initialize(parent=nil)
        @layout = Qt::HBoxLayout.new
        super(parent)
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

#--------------------------------------------------------------------------
#
#
class SettingsBase < KDE::ConfigSkeleton
    include Singleton

    public
    # @sym : instance symbol to be added.
    def addBoolItem(sym, default=true)
        name = sym.to_s
        defineItem(sym, 'value', ItemBool, default)
    end

    def addStringItem(sym, default="")
        defineItem(sym, 'toString', ItemString, default)
    end

    def addUrlItem(sym, default=KDE::Url.new)
        if default.kind_of? String then
            default = KDE::Url.new(default)
        end
        defineItem(sym, 'value', ItemUrl, default)
    end

    def addStringListItem(sym, default="")
        defineItem(sym, 'value', ItemStringList, default)
    end

    def addChoiceItem(name, list, default=0)
        choices = makeChoices(list)
        defineItemProperty(name, 'value')
        item = ItemEnum.new(currentGroup, name.to_s, default, choices, default)
        addItem(item)
    end

    def [](name)
        findItem(name)
    end

    protected
    def makeChoices(list)
        choices = []
        list.each do |i|
            c = ItemEnum::Choice.new
            c.name = i
            choices << c
        end
        choices
    end

    def defineItem(name, valueMethod, itemClass, default)
        defineItemProperty(name, valueMethod)
        item = itemClass.__send__(:new, currentGroup, name.to_s, default, default)
        addItem(item)
    end

    def defineItemProperty(name, valueMethod)
        self.class.class_eval %Q{
            def #{name}
                findItem('#{name}').property.#{valueMethod}
            end

            def self.#{name}
                s = self.instance
                s.#{name}
            end

            def set#{name}(v)
                item = findItem('#{name}')
                unless item.immutable?
                    item.property = @#{name} = Qt::Variant.fromValue(v)
                end
            end

            def self.set#{name}(v)
                s = self.instance
                s.set#{name}(v)
            end

            def #{name}=(v)
                set#{name}(v)
            end

            def self.#{name}=(v)
                self.set#{name}(v)
            end
        }
    end
end

#--------------------------------------------------------------------------
#
#


class String
    def double_quote
        '"' + self + '"'
    end
    alias   :dquote :double_quote

    def single_quote
        "'" + self + "'"
    end
    alias   :squote :single_quote

    def _chomp_null
        gsub(/\0.*/, '')
    end

    def sql_quote
        str = _chomp_null
        return 'NULL' if str.empty?
        "'#{str.sql_escape}'"
    end

    def sql_escape
        str = _chomp_null
        str.gsub(/\\/, '\&\&').gsub(/'/, "''")    #'
    end
end


module Enumerable
    class Proxy
        instance_methods.each { |m| undef_method(m) unless m.match(/^__/) }
        def initialize(enum, method=:map)
            @enum, @method = enum, method
        end
        def method_missing(method, *args, &block)
            @enum.__send__(@method) {|o| o.__send__(method, *args, &block) }
        end
    end

    def every
        Proxy.new(self)
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