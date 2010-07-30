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
        @fileName = fName

        @stage = DOWNLOAD
        @status = STOP

        connect(self, SIGNAL('finished(int,QProcess::ExitStatus)'), self, SLOT('taskFinished(int,QProcess::ExitStatus)') )
    end


    public
    def beginTask
        # 1st stage : download
        beginDownload
    end

    def nextTask
        allTaskFinished
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
        self.status = RUNNING
        @currentCommand = makeMPlayerDownloadCmd
        start(@currentCommand.app, @currentCommand.args)
#             start("./testjob.rb")
#             start("./testarg.rb", @currentCommand.args)
        $log.info { @currentCommand.msg }
    end

    def beginConvert
        fName = @fileName
        newf = fName.gsub(/\.\w+$/i, '.mp3')

        cmd = "nice -n 19 ffmpeg -i '#{f}' -f mp3 '#{newf}'"

    end

    def makeMPlayerDownloadCmd
        # make MPlayer Downlaod comand
        cmdMsg = "mplayer -noframedrop -dumpfile %s -dumpstream %s" %
                    [@fileName.shellescape, @sourceUrl.shellescape]
        cmdApp = "mplayer"
        cmdArgs = ['-noframedrop', '-dumpfile', @fileName, '-dumpstream', @sourceUrl]
        $log.info{ ["Execute following command.", cmdMsg] }
        Command.new( cmdApp, cmdArgs, cmdMsg )
    end

    public
    def status=(st)
        @status = st
        taskItem.status = status
        $log.misc { "status:#{status}" }
    end

    def status
        %w( Running Error Finished )[@status]
    end

    def updateLapse
        taskItem.updateTime(lapse)
    end

    def lapse
        Time.now - @startTime
    end

    # slot :
    def taskFinished(exitCode, exitStatus)
        lastMsg = readAllStandardOutput.data .reject do |l| l.empty? end
        $log.info { lastMsg }
        if (exitCode || exitStatus) && !(lastMsg =~ /Everything done/i) then
            self.status = ERROR
            $log.error { makeErrorMsg }
        else
            nextTask
        end
    end

    def updateView
        if running? then
            # update Lapse time
            updateLapse

            # dump IO message buffer
            $log.info{ readAllStandardOutput.data .reject do |l| l.empty? end }
        end
    end


    protected
    def allTaskFinished
        $log.info { "'#{@fileName}' Downloading finished." }
        @stage = FINISHED
        self.status = STOP
    end

    def makeErrorMsg
        [ "Failed to download a File '%#2$s'",
            "Failed to convert a File '%#2$s'", ][@stage] %
            [ @sourceUrl, @fileName ]
    end
end
