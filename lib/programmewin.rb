#---------------------------------------------------------------------------------------------
#
#
class ProgrammeTableWidget < Qt::TableWidget
    include Broadcaster
    #
    #
    TITLE_COL, CATEGORIES_COL, UPDATED_COL, ON_AIR_COL, DURATION_COL, SAVED_COL = (0..5).to_a
    LABELS = %w{Title Categories Updated On\ Air Duration Saved}
    class Programme
        attr_reader :titleItem, :categoriesItem, :updatedItem, :onAirItem, \
                :durationItem, :savedItem
        alias :id :titleItem
        attr_reader :content, :url, :link
        attr_reader :updated, :onAirDate, :duration
        attr_reader :progInfo
        attr_accessor :deletedFlag
#         DATE_FORMAT = "%Y/%m/%d %a"

        def initialize(title, categories, updated, content, link)
            @progInfo = BBCNet::ProgrammeInfo.new(title, categories, updated, content, link)
            @content = content
            @url = content[UrlRegexp]
            @link = link
            @updated = BBCNet.getTime(updated)
            @onAirDate = Time.zero
            @duration = 0

            @titleItem = Item.new(title)
            @categoriesItem = Item.new(categories)
            @updatedItem = DateItem.new(@updated)
            @onAirItem = DateItem.new
            @durationItem = NumItem.new
            @savedItem = Item.new

# #             BBCNet::CachedMetaInfoIO.read(link, self.method(:onReadInfo))
#             minfo = @progInfo.readMetaInfo()
# 
# #             @minfo = minfo
#             return if deletedFlag
#             @onAirDate = minfo.onAirDate
#             @duration = minfo.duration
#             @onAirItem.date = @onAirDate if @onAirDate
#             @durationItem.text = @duration.to_s if @duration
        end

        def title
            @titleItem.text
        end

        def categories
            @categoriesItem.text
        end

        def saved
            @savedItem.text
        end
    end

    #
    #
    class Item < Qt::TableWidgetItem
        def initialize(text='')
            super(text)
            self.flags = Qt::ItemIsSelectable | Qt::ItemIsEnabled
            self.toolTip = text
        end
    end

    class NumItem < Item
        def lessThan(i)
            self.text.to_i < i.text.to_i
        end
        alias :'operator<' :lessThan
    end

    class DateItem < Item
        def initialize(d=Time.zero)
            super('')
            self.date = d
        end
        attr_reader :date

        def lessThan(o)
            date < o.date
        end
        alias :'operator<' :lessThan

        def date=(d)
            @date = d
            if d.zero? then
                self.toolTip = self.text = ''
            else
                self.toolTip = self.text = d.to_s   #strftime(DATE_FORMAT)
            end
        end
    end

    #------------------------------------------------------------------------
    #
    #

    def initialize()
        super(0, 6)

        setHorizontalHeaderLabels(LABELS)
        self.horizontalHeader.stretchLastSection = true
        self.selectionBehavior = Qt::AbstractItemView::SelectRows
        self.alternatingRowColors = true
        self.sortingEnabled = true
        sortByColumn(2, Qt::DescendingOrder )


        # Hash table : key column_0_item  => Programme entry.
        @table = Hash.new
    end

    def clearEntries
        clearContents
        self.rowCount = 0
        @table.each do |k,prog|
            prog.deletedFlag = true
        end
        @table = Hash.new
    end

    def setEntry( row, title, categories, updated, content, link )
        entry = Programme.new(title, categories, updated, content, link)
        setItem( row, TITLE_COL, entry.titleItem )
        setItem( row, CATEGORIES_COL, entry.categoriesItem )
        setItem( row, UPDATED_COL, entry.updatedItem )
        setItem( row, ON_AIR_COL, entry.onAirItem )
        setItem( row, DURATION_COL, entry.durationItem )
        setItem( row, SAVED_COL, entry.savedItem )
        @table[entry.id] = entry
    end

    def addEntriesFromRss(rss)
        entries = rss.css('entry')
        clearEntries
        return unless rss and entries and entries.size

        sortFlag = sortingEnabled
        self.sortingEnabled = false
        hide
        self.rowCount = entries.size

        # ['Title', 'Category', 'Updated' ]
        entries.each_with_index do |e, row|
            title = e.at_css('title').content
            updated = e.at_css('updated').content
            content = e.at_css('content').content
            linkItem = e.css('link').find do |l| l['rel'] == 'self' end
            link = linkItem ? linkItem['href'] : nil
            categories = e.css('category').map do |c| c['term'] end.join(',')
            $log.misc { title }
            setEntry( row, title, categories, updated, content, link )
        end

        self.sortingEnabled = sortFlag
        show
    end

    # return Programme object.
    def [](row)
        @table[item(row,0)]
    end


    #
    # slot : called when filterLineEdit text is changed.
    #
    public
    slots   'filterChanged(const QString &)'
    def filterChanged(text)
        return unless text

        regxs = text.split(/[,\s]+/).map do |w|
                    /#{Regexp.escape(w.strip)}/i
        end
        rowCount.times do |r|
            i0 = item(r,0)
            i1 = item(r,1)
            i2 = item(r,2)
            txt = ((i0 && i0.text) || '') + ((i1 && i1.text) || '') + ((i2 && i2.text) || '')
            if regxs.all? do |rx| rx =~ txt end then
                showRow(r)
            else
                hideRow(r)
            end
        end
    end

    GroupName = "ProgrammeTable"
    def writeSettings
        config = $config.group(GroupName)
        config.writeEntry('Header', horizontalHeader.saveState)
    end

    def readSettings
        config = $config.group(GroupName)
        horizontalHeader.restoreState(config.readEntry('Header', horizontalHeader.saveState))
    end

    protected
    def contextMenuEvent(e)
        item = itemAt(e.pos)
        return unless item
        prog = self[item.row]
        menu = createPopup
        action = menu.exec(e.globalPos)
        action and execPopup(action, prog)
        menu.deleteLater
    end

    def createPopup()
        menu = Qt::Menu.new
        a = menu.addAction(KDE::Icon.new('search'), i18n('Search Same Programme'))
        a.setVData('searchSame@')
        a = menu.addAction(KDE::Icon.new('search'), i18n('Search Same Category tags'))
        a.setVData('searchSameTags@')
        menu.addSeparator
        insertSchedule(menu)
        menu.addSeparator
        insertPlayerActions(menu)
        menu
    end

    def execPopup(action, item)
        $log.code { "execute : '#{action.vData}'" }
        cmd, exe = action.vData.split(/@/, 2)
        $log.code { "cmd(#{cmd}), exe(#{exe})" }
        if cmd == 'play'
            playMedia(exe, item)
        elsif self.respond_to?(cmd)
            self.method(cmd).call(item)
        else
            $log.warn { "No method #{cmd} in contextmenu." }
        end
    end

    def insertSchedule(menu)
        a = menu.addAction(KDE::Icon.new('view-time-schedule'), i18n('Schedule This Title Programmes'))
        a.setVData('scheduleByTitle@')
        a = menu.addAction(KDE::Icon.new('view-time-schedule'), i18n('Schedule This Time'))
        a.setVData('scheduleByTime@')
    end

    def insertPlayerActions(menu)
        Mime::services('.wma').each do |s|
            exeName = s.exec[/\w+/]
            a = menu.addAction(KDE::Icon.new(exeName), 'Play with ' + exeName)
            a.setVData('play@' + s.exec)
        end
    end

    def playMedia(exe, prog)
        url = prog.content[UrlRegexp]       # String[] method extract only 1st one.

        $log.info { "playMedia episode Url:#{url}, exe:#{exe}" }
        minfo = BBCNet::CachedMetaInfoIO.read(url)
        streamInfo = minfo.streamInfo
        return unless streamInfo
        url = streamInfo.url

        args = exe.split(/\s+/)
        cmd = args.shift
        args = args.map do |a|
            case a
            when /%c/
                a.gsub(/%c/, prog.title)
            else    
                a.gsub(/%\w/, url)
            end
        end
        $log.debug { "execute cmd '#{cmd}', args '#{args.inspect}'" }
        proc = Qt::Process.new(self)
        proc.start(cmd, args)
    end

    signals  'filterRequest(const QString &)'
    def searchSame(prog)
        emit filterRequest( prog.title.sub(/:.*/, '') )
    end

    def searchSameTags(prog)
        emit filterRequest( prog.categories )
    end

    def scheduleByTitle(prog)
        broadcast(:addFilterByTitle, prog.progInfo)
    end

    def scheduleByTime(prog)
        broadcast(:addFilterByTime, prog.progInfo)
    end
end


