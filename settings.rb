#
#    2007 by ruby.twiddler@gmail.com
#
require 'kio'

class Settings < SettingsBase
    def initialize
        super()

        setCurrentGroup("Preferences")

        # meta programed version.
        addBoolItem(:installInSystemDirFlag, true)
        addUrlItem(:rawDownloadDir, KDE::GlobalSettings.downloadPath + '/RadioRaw')
        addUrlItem(:finalDownloadDir, KDE::GlobalSettings.downloadPath + '/Radio')
    end

end


#--------------------------------------------------------------------------
#
#
class SettingsDlg < KDE::ConfigDialog
    def initialize(parent)
        super(parent, "Settings", Settings.instance)
        addPage(FolderSettingsPage.new, i18n("Folder"), 'folder')
    end
end


#--------------------------------------------------------------------------
#
#
class FolderSettingsPage < Qt::Widget

    def initialize(parent=nil)
        super(parent)
        createWidget
        loadSettings
    end

    attr_reader :fileLine, :browserCombo
    def createWidget
        @rawFileDirLine = KDE::UrlRequester.new(KDE::Url.new(KDE::GlobalSettings.downloadPath))
        @rawFileDirLine.mode = KDE::File::Directory | KDE::File::LocalOnly

        @finalFileDirLine = KDE::UrlRequester.new(KDE::Url.new(KDE::GlobalSettings.downloadPath))
        @finalFileDirLine.mode = KDE::File::Directory | KDE::File::LocalOnly

        # objectNames
        @rawFileDirLine.objectName = 'kcfg_RawDownloadDir'
        @finalFileDirLine.objectName = 'kcfg_FinalDownloadDir'

        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(Qt::Label.new(i18n('Raw File Download Directory')))
            l.addLayout(Qt::HBoxLayout.new do |hl|
                        hl.addWidget(Qt::Label.new('  '))
                        hl.addWidget(@rawFileDirLine)
                       end
                       )
            l.addWidget(Qt::Label.new(i18n('Final File Download Directory')))
            l.addLayout(Qt::HBoxLayout.new do |hl|
                        hl.addWidget(Qt::Label.new('  '))
                        hl.addWidget(@finalFileDirLine)
                       end
                       )
            l.addStretch
        end

        setLayout(lo)
    end

    def loadSettings
    end
end

