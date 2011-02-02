#-------------------------------------------------------------------------------------------
#
#  Task Window
#
class ScheduleWindow < Qt::Widget

    #--------------------------------------------
    #
    #
    class ProgrammeFilterTable < Qt::TableWidget
        #
        #
        class Item < Qt::TableWidgetItem
            def initialize(text)
                super(text)
                self.flags = Qt::ItemIsSelectable | Qt::ItemIsEnabled
                self.toolTip = text
            end
        end

        #
        #
        class ProgrammeFilter
            attr_reader :title, :categories, :catIndex, :titleFilter, :folder
            attr_reader :categoriesItem, :titleFilterItem, :timeItem, :intervalItem, :folderItem
            def initialize(title, categories, folder)
                $log.debug { "title:#{title}, categories:#{categories}, folder:#{folder}" }

                @title = title
                @categories = categories
                @catIndex = BBCNet::getCategoryIndex(categories)

                # set title filter
                @titleFilter = Regexp.new( @title.gsub(/^[^:]+ Catch\-Up:/, '') \
                    .gsub(/:[\d\/\s]+$/, '') .gsub(/:\s*Episode[\s\d]*$/, '') .gsub(/:.*$/, '') )

                #
                @time = Time.at(0)
                @interval = Time.at(0)
                @folder = folder

                # item
                @categoriesItem = Item.new(@categories)
                @titleFilterItem = Item.new(@titleFilter.source)
                @timeItem = Item.new('')
                @intervalItem = Item.new('')
                @folderItem = Item.new(@folder)
            end
        end


        # column
        CATEGORY_COL, PROGRAM_COL, TIME_COL, INTERVAL_COL, FOLDER_COL = (0..5).to_a

        attr_reader :filters
        def initialize()
            super(0,5)

            self.setHorizontalHeaderLabels(%w{Category Program Time Interval Folder})
            self.horizontalHeader.stretchLastSection = true
            self.selectionBehavior = Qt::AbstractItemView::SelectRows
            self.selectionMode = Qt::AbstractItemView::SingleSelection
            self.alternatingRowColors = true

            # Hash table : key column_0_item  => Programme entry.
            @table = Hash.new
        end

        def filters
            @table.values
        end

        def addFilterByTitle( title, categories, folder )
            filter = ProgrammeFilter.new(title, categories, folder)
            addFilter( filter )
        end

        def addFilter( filter )
            row = rowCount
            self.rowCount = row + 1
            setItem( row, CATEGORY_COL, filter.categoriesItem )
            setItem( row, PROGRAM_COL, filter.titleFilterItem )
            setItem( row, TIME_COL, filter.timeItem )
            setItem( row, INTERVAL_COL, filter.intervalItem )
            setItem( row, FOLDER_COL, filter.folderItem )
            @table[filter.categoriesItem] = filter
        end
    end


    #--------------------------------------------
    #
    #
    def initialize(downloader)
        super()

        @downloader = downloader
        createWidget
    end

    def createWidget
        # create widgets
        @programmeFilterTable = ProgrammeFilterTable.new

        # layout
        vLayout = Qt::VBoxLayout.new
        vLayout.addWidget(@programmeFilterTable)

        setLayout(vLayout)
    end


    slots :updateFilteredProgrammes
    def updateFilteredProgrammes
        catIndices = {}
        @programmeFilterTable.filters.each do |f|
            if catIndices[f.catIndex] then
                catIndices[f.catIndex] += f
            else
                catIndices[f.catIndex] = [f]
            end
        end
        catIndices.delete(-1)

        catIndices.each do |catIndex, filters|
            rss = BBCNet::getRssByCategoryIndex(catIndex)
            entries = rss.css('entry')
            if rss and entries and entries.size then
                filters.each do |filter|
                    entries.each do |e|
                        title = e.at_css('title').content
                        if filter.titleFilter.match(title) then
#                             updated = e.at_css('updated').content
                            content = e.at_css('content').content
#                             linkItem = e.css('link').find do |l| l['rel'] == 'self' end
#                             link = linkItem ? linkItem['href'] : nil
#                             categories = e.css('category').map do |c| c['term'] end.join(',')
                            $log.misc { title }
                            episodeUrl = content[UrlRegexp]       # String[] method extract only 1st one.
                            addProgramme( filter, title, episodeUrl )
                        end
                    end
                end
            end
        end
    end

    slots 'addProgrammeFilter(const QString &, const QString &)'
    def addProgrammeFilter(title, categories)
        folder = @downloader.getSaveFolder(categories)
        # add filter
        @programmeFilterTable.addFilterByTitle( title, categories, folder )
    end

    #
    #
    protected
    def addProgramme( filter, title, episodeUrl )
        # download
        $log.debug { "download item { title:#{title}, epUrl:#{episodeUrl} }" }
    end
end
