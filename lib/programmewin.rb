
#---------------------------------------------------------------------------------------------
#
#
class ProgrammeTableWidget < Qt::TableWidget
    #
    #
    class Programme
        attr_reader :titleItem, :categoriesItem, :updatedItem
        attr_reader :content, :link

        def initialize(title, categories, updated, content, link)
            @titleItem = Item.new(title)
            @categoriesItem = Item.new(categories)
            @updatedItem = Item.new(updated)
            @content = content
            @link = link
        end

        def title
            @titleItem.text
        end

        def categories
            @categoriesItem.text
        end

        def updated
            @updatedItem.text
        end
    end

    #
    #
    class Item < Qt::TableWidgetItem
        def initialize(text)
            super(text)
            self.flags = Qt::ItemIsSelectable | Qt::ItemIsEnabled
            self.toolTip = text
        end
    end


    #------------------------------------------------------------------------
    #
    #

    def initialize()
        super(0, 3)

        setHorizontalHeaderLabels(['Title', 'Category', 'Updated'])
        self.horizontalHeader.stretchLastSection = true
        self.selectionBehavior = Qt::AbstractItemView::SelectRows
        self.alternatingRowColors = true
        self.sortingEnabled = true
        sortByColumn(2, Qt::DescendingOrder )


        # Hash table : key column_0_item  => Programme entry.
        @table = Hash.new
    end

    def addEntry( row, title, categories, updated, content, link )
        entry = Programme.new(title, categories, updated, content, link)
        setItem( row, 0, entry.titleItem )
        setItem( row, 1, entry.categoriesItem )
        setItem( row, 2, entry.updatedItem )
        @table[entry.titleItem] = entry
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
        a = menu.addAction('Schedule This Title Programme')
        a.setVData('schedule@')
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
        reply = CachedIO::CacheReply.new(url, nil)
        reply.obj = exe
        BBCNet::CachedMetaInfoIO.read(url, \
                reply.finishedMethod(self.method(:playMediaAtReadInfo)))
    end

    def playMediaAtReadInfo(reply)
        minfo = reply.data
        exe = reply.obj
        streamInfo = minfo.streamInfo
        return unless streamInfo
        url = streamInfo.url

        cmd, args = exe.split(/\s+/, 2)
        args = args.split(/\s+/).map do |a|
            a.gsub(/%\w/, url)
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

    signals 'scheduleRequest(const QString &, const QString &)'
    def schedule(prog)
        emit scheduleRequest( prog.title, prog.categories )
    end
end


