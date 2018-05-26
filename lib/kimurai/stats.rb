require 'sequel'
require 'sqlite3'
require 'json'

module Kimurai
  class Stats
    DB = Sequel.connect(Kimurai.configuration.stats_database)

    DB.create_table?(:sessions) do
      primary_key :id, type: :integer, auto_increment: false
      string :status
      datetime :start_time, empty: false
      datetime :stop_time
      integer :concurrent_jobs
      text :crawlers
      text :error
    end

    DB.create_table?(:runs) do
      primary_key :id
      string :crawler_name, empty: false
      string :status
      string :environment
      datetime :start_time, empty: false
      datetime :stop_time
      float :running_time
      foreign_key :session_id, :sessions
      foreign_key :crawler_id, :crawlers
      text :visits
      text :items
      text :error
      text :server
    end

    DB.create_table?(:crawlers) do
      primary_key :id
      string :name, empty: false, unique: true
    end

    class Session < Sequel::Model(DB)
      one_to_many :runs

      plugin :json_serializer
      plugin :serialization
      plugin :serialization_modification_detection
      serialize_attributes :json, :crawlers

      unrestrict_primary_key

      def total_time
        (stop_time ? stop_time - start_time : Time.now - start_time).round(3)
      end

      def processing?
        status == "processing"
      end

      def crawlers_in_queue
        return [] unless processing?
        crawlers - runs_dataset.select_map(:crawler_name)
      end

      def running_runs
        runs_dataset.where(status: "running").all
      end

      def failed_runs
        runs_dataset.where(status: "failed").all
      end

      def completed_runs
        runs_dataset.where(status: "completed").all
      end
    end

    class Run < Sequel::Model(DB)
      many_to_one :session
      many_to_one :crawler

      plugin :json_serializer
      plugin :serialization
      plugin :serialization_modification_detection
      serialize_attributes :json, :visits, :items, :server

      # scopes
      dataset_module do
        def crawler_id(id)
          filter(crawler_id: id)
        end

        def session_id(id)
          filter(session_id: id)
        end
      end
    end

    class Crawler < Sequel::Model(DB)
      one_to_many :runs

      plugin :json_serializer

      def current_session
        session = Session.find(status: "processing")
        return unless session
        session if session.crawlers.include?(name)
      end

      def running?
        runs_dataset.first(status: "running") ? true : false
      end

      def current_state
        running? ? "running" : "stopped"
      end
    end
  end
end