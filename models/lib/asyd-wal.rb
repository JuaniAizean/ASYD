module Awal
  class Mutex < ProcessShared::Mutex
    def initialize
      @last_lock = ProcessShared::SharedMemory.new(:int)
      @last_lock.put_int(0, 0)
      super
    end

    def last_lock
      @last_lock.get_int(0)
    end

    def last_lock=(stamp)
      @last_lock.put_int(0, stamp)
    end

    def synchronize
      lock
      @last_lock.put_int(0, 1)
      begin
        yield
      ensure
        @last_lock.put_int(0, Time.now.to_i)
        unlock
      end
    end
  end

  # Checkpoints a given database
  #
  def self.checkpoint(database)
    begin
      ret = repository(database).adapter.select('PRAGMA wal_checkpoint(FULL)')
      puts "Checkpointed "+database.to_s+": "+ret.to_s if $DBG == 1
      raise if ret[0].busy == 1
      return true
    rescue
      return false
    end
  end

  # Runs on backgound and check if there's checkpointeable changes
  #
  def self.should_checkpoint?
    Signal.trap("TERM") {
      Awal::checkpoint(:users_db)
      Awal::checkpoint(:config_db)
      Awal::checkpoint(:stats_db)
      Awal::checkpoint(:status_db)
      Awal::checkpoint(:monitoring_db)
      Awal::checkpoint(:tasks_db)
      Awal::checkpoint(:notifications_db)
      Awal::checkpoint(:hosts_db)
      exit
    }

    while true
      stamp = Time.now.to_i
      if NOTEX.last_lock > 1
        if stamp > (NOTEX.last_lock + 10)
          chp = false
          NOTEX.synchronize do
            chp = checkpoint(:notifications_db)
          end
          if chp
            NOTEX.last_lock = 0
          end
        end
      end
      if TATEX.last_lock > 1
        if stamp > (TATEX.last_lock + 10)
          chp = false
          TATEX.synchronize do
            chp = checkpoint(:tasks_db)
          end
          if chp
            TATEX.last_lock = 0
          end
        end
      end
      if HOSTEX.last_lock > 1
        if stamp > (HOSTEX.last_lock + 10)
          chp = false
          HOSTEX.synchronize do
            chp = checkpoint(:hosts_db)
          end
          if chp
            HOSTEX.last_lock = 0
          end
        end
      end
      sleep 20
    end
  end
end
