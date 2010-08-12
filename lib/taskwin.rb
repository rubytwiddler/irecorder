#---------------------------------------------------------------------------------------------------
#
#  Task Window
#
class TaskWindow < Qt::Widget

    # column
    SOURCE = 0
    FILE = 1
    LAPSE = 2
    STATUS = 3

    class TaskItem
        attr_reader :sourceUrlItem, :savePathItem, :savePath
        attr_reader :timeItem, :statusItem
        attr_reader :process
        alias   :id :sourceUrlItem

        def initialize(process, src, save, time, status)
            @sourceUrlItem = Item.new(src)
            @savePathItem = Item.new(File.basename(save))
            @timeItem = Item.new(lapseText(time))
            @statusItem = Item.new(status)
            @process = process
            @savePath = save
        end

        def sourceUrl
            @sourceUrlItem.text
        end

        def time
            @timeItem.text
        end

        def status
            @statusItem.text
        end

        def updateTime(lapse)
            @timeItem.text = lapseText(lapse)
        end

        def status=(str)
            @statusItem.text = str
        end

        def lapseText(lapse)
            a = Time.at(lapse).getgm.to_a
            "%02d:%02d:%02d" % [a[2], a[1], a[0]]
        end

    end


    #--------------------------------------------
    #
    #
    class TaskTable < Qt::TableWidget

        def initialize
            super(0,4)

            # Hash table : key column_0_item  => TaskItem
            @taskItemTbl = {}
        end

        public
        def taskItemAtRow(row)
            i0 = item(row,0)     # column_0_item is key to taskItem ID
            i0 && taskItemFromId(i0)
        end

        def taskItemFromId(id)
            @taskItemTbl[id]
        end

        def insertTaskItem(taskItem)
            sortFlag = sortingEnabled
            self.sortingEnabled = false

            insertRow(0)
            setItem(0,SOURCE, taskItem.sourceUrlItem)
            setItem(0,FILE, taskItem.savePathItem)
            setItem(0,LAPSE, taskItem.timeItem)
            setItem(0,STATUS, taskItem.statusItem)
            @taskItemTbl[taskItem.id] = taskItem

            self.sortingEnabled = sortFlag
        end

        def each(&block)
            a = []
            rowCount.times do |r|
                i = taskItemAtRow(r)
                a << i if i
            end
            a.each do |i| block.call( i ) end
        end

        def deleteItem(i)
            removeRow(i.id.row)
            @taskItemTbl.delete(i.id)
        end


        # context menu : right click popup menu.
        protected
        def contextMenuEvent(e)
            $log.misc { "right button is clicked." }
            wItem = itemAt(e.pos)
            if wItem
                openContextPopup(e.globalPos, wItem)
            end
        end




        # open & exec contextMenu
        def openContextPopup(pos, wItem)
            poRow =  wItem.row
            poColumn = wItem.column
            $log.misc { "right clicked item (row:#{poRow}, column:#{poColumn})" }
            url = getContextUrl(wItem)
            sts = taskItemAtRow(wItem.row).status

            menu = Qt::Menu.new
            insertDefaultActions(menu, poColumn, url, sts)
            if url then
                menu.addSeparator
                insertPlayerActions(menu, url)
                menu.addSeparator
                insertMPlayerAction(menu)
            end
            action = menu.exec(pos)
            if action then
                $log.code { "execute : '#{action.data.toString}'" }
                cmd, exe = action.data.toString.split(/@/, 2)
                $log.code { "cmd(#{cmd}), exe(#{exe})" }
                case cmd
                when 'play'
                    playMedia(exe, wItem)
                else
                    self.method(cmd).call(wItem)
                end
            end
            menu.deleteLater
        end

        def insertDefaultActions(menu, poColumn, url, sts)
            a = menu.addAction(KDE::Icon.new('edit-copy'), 'Copy Text')
            a.setVData('copyText@')
            if poColumn == FILE
                a = menu.addAction(KDE::Icon.new('kfm'), 'Open Folder')
                a.setVData('openFolder@')
                a = menu.addAction(KDE::Icon.new('kfm'), 'Open Temp Folder')
                a.setVData('openTempFolder@')
            end
            if sts =~ /Error/i
                a = menu.addAction(KDE::Icon.new('view-refresh'), 'Retry')
                a.setVData('retryTask@')
                a = menu.addAction(KDE::Icon.new('list-remove'), 'Remove')
                a.setVData('removeTask@')
            end
            if sts =~ /\w+ing\b/i
                a = menu.addAction(KDE::Icon.new('edit-delete'), 'Cancel')
                a.setVData('cancelTask@')
            end
            a = menu.addAction(KDE::Icon.new('edit-clear-list'), 'Clear All Finished.')
            a.setVData('clearAllFinished@')
            a = menu.addAction(KDE::Icon.new('edit-clear-list'), 'Clear All Errors.')
            a.setVData('clearAllErrors@')
        end


        def insertMPlayerAction(menu)
            player = 'mplayer'
            mplayerPath = %x(which #{player})
            return if mplayerPath =~ /no #{player}/
            insertPlayer(menu, player, player +  ' %U')
        end

        def insertPlayerActions(menu, url)
            Mime::services(url).each do |s|
                if s.exec then
                    exeName = s.exec[/\w+/]
                    insertPlayer(menu, exeName, s.exec)
                end
            end
        end

        def insertPlayer(menu, exeName, exec = exeName)
            a = menu.addAction(KDE::Icon.new(exeName), 'Play with ' + exeName)
            a.setVData('play@' + exec)
        end


        def getContextUrl(wItem)
            ti = taskItemAtRow(wItem.row)
            return nil unless ti
            rawFilePath = File.join(IRecSettings.rawDownloadDir.path, ti.savePath)
            filePath = File.join(IRecSettings.downloadDir.path, ti.savePath)
            url =   case wItem.column
                    when SOURCE
                        ti.sourceUrl
                    when FILE
                        ti.process.rawDownloaded? ? filePath : rawFilePath
                    else
                        nil
                    end
        end


        # contextMenu Event
        def playMedia(exe, wItem)
            url = getContextUrl(wItem)
            return unless url
            cmd, args = exe.split(/\s+/, 2)
            args = args.split(/\s+/).map do |a|
                a.gsub(/%\w/, url)
            end
#             cmd = 'test/testarg.rb'     # debug test
            $log.debug { "execute cmd '#{cmd}', args '#{args.inspect}'" }
            proc = Qt::Process.new(self)
            proc.start(cmd, args)
        end

        # contextMenu Event
        def copyText(wItem)
            $app.clipboard.setText(wItem.text)
        end

        # contextMenu Event
        def retryTask(wItem)
            ti = taskItemAtRow(wItem.row)
            if ti and ti.process.error? then
                ti.process.retryTask
                $log.info { "task restarted." }
            end
        end

        # contextMenu Event
        def cancelTask(wItem)
            ti = taskItemAtRow(wItem.row)
            if ti and ti.process.running? then
                ti.process.cancelTask
                $log.info { "task canceled." }
            end
        end

        # contextMenu Event
        def removeTask(wItem)
            ti = taskItemAtRow(wItem.row)
            if ti and ti.process.running? then
                ti.process.cancelTask
                $log.info { "task canceled." }
            end
            deleteItem(ti)
        end

        # contextMenu Event
        def openFolder(wItem)
            ti = taskItemAtRow(wItem.row)
            return unless ti
            filePath = File.join(IRecSettings.downloadDir.path, File.dirname(ti.savePath))
            proc = Qt::Process.new(self)
            proc.start('dolphin', [filePath])
        end

        # contextMenu Event
        def openTempFolder(wItem)
            ti = taskItemAtRow(wItem.row)
            return unless ti
            rawFilePath = File.join(IRecSettings.rawDownloadDir.path, File.dirname(ti.savePath))
            proc = Qt::Process.new(self)
            proc.start('dolphin', [rawFilePath])
        end

        # contextMenu Event
        def clearAllFinished(wItem)
            self.each do |i|
                deleteItem(i) if i.process.finished?
            end
        end

        # contextMenu Event
        def clearAllErrors(wItem)
            self.each do |i|
                deleteItem(i) if i.process.error?
            end
        end

    end

    #--------------------------------------------
    #
    #
    class Item < Qt::TableWidgetItem
        def initialize(text)
            super(text)
            self.flags = Qt::ItemIsSelectable | Qt::ItemIsUserCheckable | Qt::ItemIsEnabled
        end
    end


    #--------------------------------------------
    #
    def initialize()
        super

        # create widgets
        tvLayout = Qt::VBoxLayout.new
        @table = TaskTable.new
        tvLayout.addWidget(@table)
        @table.setHorizontalHeaderLabels(['Source', 'File', 'Lapse', 'Status'])
        @table.horizontalHeader.stretchLastSection = true
        @table.selectionBehavior = Qt::AbstractItemView::SelectRows
        @table.alternatingRowColors = true

        setLayout(tvLayout)

        # initialize variables
        #
    end

    GroupName = "TaskWindow"
    def writeSettings
        config = $config.group(GroupName)
        config.writeEntry('Header', @table.horizontalHeader.saveState)
    end

    def readSettings
        config = $config.group(GroupName)
        @table.horizontalHeader.restoreState(config.readEntry('Header', @table.horizontalHeader.saveState))
    end

    # return : added TaskItem
    public
    def addTask(process, src, save)
        # insert at the top

        taskItem = TaskItem.new(process, src, save, 0, 'prepare')
        @table.insertTaskItem(taskItem)

        taskItem
    end

    def each(&block)
        @table.each(&block)
    end
end

