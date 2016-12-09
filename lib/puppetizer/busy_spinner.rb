class BusySpinner

  def stop
    @running = false
  end

  def run
    @running = true
    progressbar = ProgressBar.create(:total=> nil, :title=>'finishing')

    while @running
      progressbar.increment
      sleep(0.2)
    end
  end

end
