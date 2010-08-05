#-------------------------------------------------------------------
#
#
#
class DownloadProcess < Qt::Process
    slots   'taskFinished(int,QProcess::ExitStatus)'
    attr_reader     :sourceUrl, :fileName
    attr_accessor   :taskItem

    # stage
    DOWNLOAD = 0
    CONVERT = 1
    FINISHED = 2

    # status
    RUNNING = 0
    ERROR = 1
    STOP = 2
    def status
        return %w{ Downloading Converting Finished }[@stage] if @status == RUNNING
        %w( Running Error Finished )[@status]
    end

    class Command
        attr_accessor   :app, :args, :msg
        def initialize(app, args, msg)
            @app = app
            @args = args
            @message = msg
        end
    end

    def initialize(parent, src, fName)
        super(parent)
        @parent = parent
        @startTime = Time.new
        @sourceUrl = src
        @rawFileName = fName
        $log.info { "@rawFileName : #{@rawFileName}" }
        $log.info { "rawDownloadDir : #{IRecSettings.rawDownloadDir.path}" }
        @rawFilePath = File.join(IRecSettings.rawDownloadDir.path, fName)
        mkdirSavePath(@rawFilePath)
        $log.info { "@rawFilePath : #{@rawFilePath }" }

        @stage = DOWNLOAD
        @status = STOP

        connect(self, SIGNAL('finished(int,QProcess::ExitStatus)'), self, SLOT('taskFinished(int,QProcess::ExitStatus)') )
    end


    public
    def beginTask
        # 1st stage : download
#         if File.exist?(@rawFilePath) then
#             $log.debug { "begin convert" }
#             beginConvert
#             return
#         end
        beginDownload
    end

    # increment stage
    def nextTask
        @stage += 1
        case @stage
        when DOWNLOAD
            @startTime = Time.new
            beginDownload
        when CONVERT
            beginConvert
        else
            removeRawFile
            allTaskFinished
        end
    end

    def retryTask
        $log.debug { "retry! in main." }
        if @status == ERROR
            # retry
            case @stage
            when DOWNLOAD
                @startTime = Time.new
                beginDownload
            when CONVERT
                beginConvert
            end
        else
            $log.warn { "cannot retry the successfully finished or running process." }
        end
    end

    def running?
        @status == RUNNING
    end

    protected
    def beginDownload
        @stage = DOWNLOAD
        @downNG = true
        self.status = RUNNING
        @currentCommand = makeMPlayerDownloadCmd

        start(@currentCommand.app, @currentCommand.args)
        $log.info { @currentCommand.msg }
    end

    def makeMPlayerDownloadCmd
        # make MPlayer Downlaod comand
        cmdMsg = "mplayer -noframedrop -dumpfile %s -dumpstream %s" %
                    [@rawFilePath.shellescape, @sourceUrl.shellescape]
        cmdApp = "mplayer"
        cmdArgs = ['-noframedrop', '-dumpfile', @rawFilePath, '-dumpstream', @sourceUrl]

#         # debug code.
#         cmdApp = "touch"
#         cmdArgs = [ @rawFilePath ]

        Command.new( cmdApp, cmdArgs, cmdMsg )
    end

    def beginConvert
        @stage = CONVERT
        self.status = RUNNING
        @outFileName = @rawFileName.gsub(/\.\w+$/i, '.mp3')
        @outFilePath = File.join(IRecSettings.downloadDir.path, @outFileName)
        mkdirSavePath(@outFilePath)

        cmdMsg = "nice -n 19 ffmpeg -i %s -f mp3 %s" %
                    [ @rawFilePath.shellescape, @outFilePath.shellescape]
        cmdApp = "nice"
        cmdArgs = [ '-n', '19', 'ffmpeg', '-i', @rawFilePath, '-f', 'mp3', @outFilePath ]

#         # debug code.
#         cmdApp = "cp"
#         cmdArgs = [ '-f', @rawFilePath, @outFilePath ]

        @currentCommand = Command.new( cmdApp, cmdArgs, cmdMsg )
        start(@currentCommand.app, @currentCommand.args)
        $log.info { @currentCommand.msg }
    end


    def removeRawFile
        unless IRecSettings.leaveRawFile then
            File.delete(@rawFilePath)
        end
    end

    def checkOutput(msg)
        msgSum = msg.join(' ')
        @downNG &&= false if msgSum =~ /Everything done/i
    end

    # check and read output
    def checkReadOutput
        msg = readAllStandardOutput.data .reject do |l| l.empty? end
        checkOutput(msg)
        $log.info { msg }
    end

    # return error or not
    def checkErroredStatus
        case @stage
        when DOWNLOAD
            @downNG
        when CONVERT
            begin
                getDuration(@outFilePath) < getDuration(@rawFilePath) -4
            rescue => e
                true
            end
        else
            true
        end
    end


    public
    def status=(st)
        @status = st
        taskItem.status = status
        $log.misc { "status:#{status}" }
    end


    def updateLapse
        taskItem.updateTime(lapse)
    end

    def lapse
        Time.now - @startTime
    end

    # slot :
    def taskFinished(exitCode, exitStatus)
        checkReadOutput
        if (exitCode.to_i.nonzero? || exitStatus.to_i.nonzero?) && checkErroredStatus then
            self.status = ERROR
            msgs = [ makeErrorMsg, "exitCode=#{exitCode}, exitStatus=#{exitStatus}" ]
            $log.error { msgs }
        else
            nextTask
        end
    end


    def updateView
        if running? then
            # update Lapse time
            updateLapse

            # dump IO message buffer
            checkReadOutput
        end
    end


    protected
    def allTaskFinished
        $log.info { "'#{@rawFilePath}' Downloading finished." }
        @stage = FINISHED
        self.status = STOP
    end

    def makeErrorMsg
        [ "Failed to download a File '%#2$s'",
            "Failed to convert a File '%#2$s'", ][@stage] %
            [ @sourceUrl, @rawFilePath ]
    end


    def mkdirSavePath(fName)
        dir = File.dirname(fName)
        unless File.exist? dir
            $log.info{ "mkdir : " +  dir }
            FileUtils.mkdir_p(dir)
        end
    end
end
