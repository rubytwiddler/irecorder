#
#    2007 by ruby.twiddler@gmail.com
#
require "mylibs.rb"


#--------------------------------------------------------------------------
#
# select from traders, system menu, arbitarary file.
#
class SelectServiceDlg < KDE::Dialog
    def initialize(parent, defaultName=nil)
        super(parent)
        @message = i18n('Select Application')
        userInitialize
        self.windowTitle = @message
        @selectedName = @services[0].name
        createWidget
        connect(self, SIGNAL(:accepted), self, SLOT(:selected))
        setSelected(defaultName)
    end

    def userInitialize
        @message = i18n('Select Application for .html file.')
        @services = Mime.services('.html')
    end

    def name
        @selectedName
    end

    def iconName
        SelectServiceDlg.exeName2IconName(serviceFromName(name).exec)
    end

    slots :selected
    def selected
        @selectedName = @serviceList.selectedItems.first.text
    end

    def commandFromName(name)
        i = serviceFromName(name)
        i && i.exec
    end

    def serviceFromName(name)
        name.gsub!(/&/, '')
        return nil if @services.size == 0
        service = @services.find(@services[0]) do |s| s.name == name end
    end

    def setSelected(name)
        return unless name
        name.gsub!(/&/, '')
        return if @services.size == 0
        unless name then
            @serviceList.takeItem(0).setSelected(true)
        else
            items = @serviceList.findItems(name, Qt::MatchExactly)
            if items.size > 0 then
                items[0].setSelected(true)
            end
        end
    end

    def self.exeName2IconName(exeName)
        iconName = exeName.gsub(%r{[^ ]*/}, '')[/([-_\w\d])+/] .
            gsub(/(dragon)/, '\1player').gsub(/kfmclient/, 'konqueror')
    end

    protected
    def createWidget
        mainWidget = VBoxLayoutWidget.new
        mainWidget.addWidget(Qt::Label.new(@message))
        @serviceList = KDE::ListWidget.new
        @services.each do |s|
            iconName = SelectServiceDlg.exeName2IconName(s.exec)
            @serviceList.addItem( Qt::ListWidgetItem.new(KDE::Icon.new(iconName), s.name) )
        end
        mainWidget.addWidget(@serviceList)

        setMainWidget(mainWidget)
    end
end


class SelectWebPlayerDlg < SelectServiceDlg
    def userInitialize
        @message = i18n('Select Web Player for iPlayer page.')
        @services = Mime.services('.html').select do |s|
            s.name !~ /office/i and
            s.serviceTypes.find do |st|
                st =~ /application\//
            end
        end
    end
end

class SelectDirectPlayerDlg < SelectServiceDlg
    def userInitialize
        @message = i18n('Select Direct Stream Player.')
        @services = Mime.services('.wma')
    end
end




#--------------------------------------------------------------------------
#
# IRecorder Settings
#
class IRecSettings < SettingsBase
    def initialize
        super()

        setCurrentGroup("Preferences")

        # meta programed version.
        addStringItem(:rawDownloadDir, Qt::Dir::tempPath + '/RadioRaw')
        addStringItem(:downloadDir, KDE::GlobalSettings.musicPath)
        addBoolItem(:dirAddMediaName, true)
        addBoolItem(:dirAddChannelName, false)
        addBoolItem(:dirAddGenreName, true)
        addStringItem(:fileAddHeadStr, 'BBC ')
        addBoolItem(:fileAddMediaName, true)
        addBoolItem(:fileAddChannelName, false)
        addBoolItem(:fileAddGenreName, true)
        addBoolItem(:leaveRawFile, false)

        addBoolItem(:playerTypeSmall, false)
        addBoolItem(:playerTypeBeta, true)

        addBoolItem(:useInnerPlayer, true)
        addBoolItem(:useWebPlayer, false)
        addStringItem(:webPlayerName, 'Konqueror')
        addBoolItem(:useDirectPlayer, false)
        addStringItem(:directPlayerName, 'KMPlayer')
    end

    def webPlayerCommand
        @webPlayerCnv.commandFromName(self.webPlayerName)
    end

    def self.webPlayerCommand
        self.instance.webPlayerCommand
    end

    def directPlayerCommand
        @directPlayerCnv.commandFromName(self.directPlayerName)
    end

    def self.directPlayerCommand
        self.instance.directPlayerCommand
    end

    def regConverter(webPlayerCnv, directPlayerCnv)
        @webPlayerCnv = webPlayerCnv
        @directPlayerCnv = directPlayerCnv
    end
end


#--------------------------------------------------------------------------
#
#
class SettingsDlg < KDE::ConfigDialog
    def initialize(parent)
        super(parent, "Settings", IRecSettings.instance)
        addPage(FolderSettingsPage.new, i18n("Folder"), 'folder', i18n('Folder and File Name'))
        addPage(PlayerSettingsPage.new, i18n("Player"), 'internet-web-browser', i18n('Player and web Browser'))
    end
end


#--------------------------------------------------------------------------
#
#
class FolderSettingsPage < Qt::Widget
    def initialize(parent=nil)
        super(parent)
        createWidget
    end

    protected

    def createWidget
        @rawFileDirLine = FolderSelectorLineEdit.new(KDE::GlobalSettings.downloadPath)
        @downloadDirLine = FolderSelectorLineEdit.new(KDE::GlobalSettings.downloadPath)

        @dirSampleLabel = Qt::Label.new('Example) ')
        @dirAddMediaName = Qt::CheckBox.new(i18n('Add media directory'))
        @dirAddChannelName = Qt::CheckBox.new(i18n('Add channel directory'))
        @dirAddGenreName = Qt::CheckBox.new(i18n('Add genre directory'))
        [ @dirAddMediaName, @dirAddChannelName, @dirAddGenreName ].each do |w|
            w.connect(SIGNAL('stateChanged(int)')) do |s| updateSampleDirName end
        end

        @fileSampleLabel = Qt::Label.new('Example) ')
        @fileAddHeadStr = KDE::LineEdit.new do |w|
            w.connect(SIGNAL('textChanged(const QString&)')) do |t| updateSampleFileName end
        end
        @fileAddMediaName = Qt::CheckBox.new(i18n('Add media name'))
        @fileAddChannelName = Qt::CheckBox.new(i18n('Add channel name'))
        @fileAddGenreName = Qt::CheckBox.new(i18n('Add genre name'))

        [ @fileAddMediaName, @fileAddChannelName, @fileAddGenreName ].each do |w|
            w.connect(SIGNAL('stateChanged(int)')) do |s| updateSampleFileName end
        end
        @leaveRawFile = Qt::CheckBox.new(i18n('Leave raw file.(don\'t delete it)'))

        # set objectNames
        #  'kcfg_' + class Settings's instance name.
        @rawFileDirLine.objectName = 'kcfg_rawDownloadDir'
        @downloadDirLine.objectName = 'kcfg_downloadDir'
        @dirAddMediaName.objectName = 'kcfg_dirAddMediaName'
        @dirAddChannelName.objectName = 'kcfg_dirAddChannelName'
        @dirAddGenreName.objectName = 'kcfg_dirAddGenreName'
        @fileAddHeadStr.objectName = 'kcfg_fileAddHeadStr'
        @fileAddMediaName.objectName = 'kcfg_fileAddMediaName'
        @fileAddChannelName.objectName = 'kcfg_fileAddChannelName'
        @fileAddGenreName.objectName = 'kcfg_fileAddGenreName'
        @leaveRawFile.objectName = 'kcfg_leaveRawFile'


        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(Qt::Label.new(i18n('Download Directory')))
            l.addWidgets('  ', @downloadDirLine)
            l.addWidget(Qt::Label.new(i18n('Temporary Raw File Download Directory')))
            l.addWidgets('  ', @rawFileDirLine)
            l.addWidget(Qt::GroupBox.new(i18n('Generating directory')) do |g|
                            vbx = Qt::VBoxLayout.new do |vb|
                                vb.addWidget(@dirSampleLabel)
                                vb.addWidget(@dirAddMediaName)
#                                 vb.addWidget(@dirAddChannelName)
                                vb.addWidget(@dirAddGenreName)
                            end
                            g.setLayout(vbx)
                        end
                        )
            l.addWidget(Qt::GroupBox.new(i18n('Generating file name')) do |g|
                            vbx = Qt::VBoxLayout.new do |vb|
                                vb.addWidget(@fileSampleLabel)
                                vb.addWidgets(i18n('Head Text'), @fileAddHeadStr)
                                vb.addWidget(@fileAddMediaName)
#                                 vb.addWidget(@fileAddChannelName)
                                vb.addWidget(@fileAddGenreName)
                            end
                            g.setLayout(vbx)
                        end
                        )
            l.addWidget(@leaveRawFile)
            l.addStretch
        end

        setLayout(lo)
    end

    def updateSampleFileName
        @fileSampleLabel.text = 'Example) ' + getSampleFileName
    end

    def checkState(checkBox)
        checkBox.checkState== Qt::Checked
    end

    def getSampleFileName
        head = @fileAddHeadStr.text
        head += 'Radio ' if checkState(@fileAddMediaName)
        head += 'Radio 7 ' if checkState(@fileAddChannelName)
        head += 'Drama '  if checkState(@fileAddGenreName)
        head += "- " unless head.empty?
        baseName = head  + 'Space Hacks Lost in Space Ship.mp3'
        baseName.gsub(%r{[\/]}, '-')
    end


    def updateSampleDirName
        @dirSampleLabel.text = 'Example) ... /' + getSampleDirName
    end

    def getSampleDirName
        dir = []
        dir << 'Radio' if checkState(@dirAddMediaName)
        dir << 'Radio 7' if checkState(@dirAddChannelName)
        dir << 'Drama' if checkState(@dirAddGenreName)
        File.join(dir.compact)
    end

end

#--------------------------------------------------------------------------
#
#
class PlayerSettingsPage < Qt::Widget
    def initialize(parent=nil)
        super(parent)
        createWidget
    end

    protected

    def createWidget
        @SelectWebPlayerDlg = SelectWebPlayerDlg.new(self, IRecSettings.webPlayerName)
        @SelectDirectPlayerDlg = SelectDirectPlayerDlg.new(self, IRecSettings.directPlayerName)
        IRecSettings.instance.regConverter(@SelectWebPlayerDlg, @SelectDirectPlayerDlg)

        @playerTypeSmall = Qt::RadioButton.new(i18n('small iplayer'))
        @playerTypeBeta = Qt::RadioButton.new(i18n('beta iplayer'))

        @innerPlayer = Qt::RadioButton.new(i18n('inner Player'))
        @webPlayer = Qt::RadioButton.new(i18n('Web Player'))
        @directPlayer = Qt::RadioButton.new(i18n('Direnct Stream Player'))

        @webPlayerName = KDE::PushButton.new('Konqueror')
        @webPlayerName.connect(SIGNAL(:pressed)) do
            @SelectWebPlayerDlg.setSelected(@webPlayerName.text)
            if @SelectWebPlayerDlg.exec == Qt::Dialog::Accepted then
                @webPlayerName.text = @SelectWebPlayerDlg.name
#                 @webPlayerName.setIcon(KDE::Icon.new(@SelectWebPlayerDlg.iconName))
                @webPlayer.checked = true
            end
        end
        @webPlayerName.setProperty("kcfg_property", Qt::Variant.new("text"))

        @directPlayerName = KDE::PushButton.new('KMPlayer')
        @directPlayerName.connect(SIGNAL(:pressed)) do
            @SelectDirectPlayerDlg.setSelected(@directPlayerName.text)
            if @SelectDirectPlayerDlg.exec == Qt::Dialog::Accepted then
                @directPlayerName.text = @SelectDirectPlayerDlg.name
#                 @directPlayerName.setIcon(KDE::Icon.new(@SelectDirectPlayerDlg.iconName))
                @directPlayer.checked = true
            end
        end
        @directPlayerName.setProperty("kcfg_property", Qt::Variant.new("text"))

        # set objectNames
        #  'kcfg_' + class Settings's instance name.
        @playerTypeSmall.objectName = 'kcfg_playerTypeSmall'
        @playerTypeBeta.objectName = 'kcfg_playerTypeBeta'
        @innerPlayer.objectName = 'kcfg_useInnerPlayer'
        @webPlayer.objectName = 'kcfg_useWebPlayer'
        @directPlayer.objectName = 'kcfg_useDirectPlayer'
        @webPlayerName.objectName = 'kcfg_webPlayerName'
        @directPlayerName.objectName = 'kcfg_directPlayerName'


        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(Qt::GroupBox.new(i18n('iPlayer Type')) do |g|
                            vbx = Qt::VBoxLayout.new do |vb|
                                vb.addWidget(@playerTypeSmall)
                                vb.addWidget(@playerTypeBeta)
                            end
                            g.setLayout(vbx)
                        end
                        )
            l.addWidget(Qt::GroupBox.new(i18n('Player')) do |g|
                            vbx = Qt::VBoxLayout.new do |vb|
                                vb.addWidget(@innerPlayer)
                                vb.addWidget(@webPlayer)
                                vb.addWidgets('  ', @webPlayerName, nil)
                                vb.addWidget(@directPlayer)
                                vb.addWidgets('  ', @directPlayerName, nil)
                            end
                            g.setLayout(vbx)
                       end
                       )
            l.addStretch
        end

        setLayout(lo)
    end
end
