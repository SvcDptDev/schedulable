module Schedulable
  module Model
    class Schedule < ActiveRecord::Base

      serialize :day
      serialize :day_of_week, Hash

      belongs_to :schedulable, polymorphic: true

      after_initialize :update_schedule
      before_save :update_schedule

      validates_presence_of :rule
      validates_presence_of :time
      validates_presence_of :date, if: Proc.new { |schedule| schedule.rule == "singular" }
      validate :validate_day, if: Proc.new { |schedule| schedule.rule == "weekly" }
      validate :validate_day_of_week, if: Proc.new { |schedule| schedule.rule == "monthly" }

      def to_icecube
        @schedule
      end

      def to_s
        message = ""
        if rule == "singular"
          # Return formatted datetime for singular rules
          datetime = DateTime.new(date.year, date.month, date.day, time.hour, time.min, time.sec, time.zone)
          message = I18n.localize(datetime)
        else
          # For other rules, refer to icecube
          begin
            message = @schedule.to_s
          rescue Exception
            locale = I18n.locale
            I18n.locale = :en
            message = @schedule.to_s
            I18n.locale = locale
          end
        end
        message
      end

      def method_missing(method_name, *args, &block)
        if @schedule.present? && @schedule.respond_to?(method_name)
          @schedule.send(method_name, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        (@schedule.present? && @schedule.respond_to?(method_name)) || super
      end

      def self.param_names
        [
          :id,
          :date,
          :time,
          :rule,
          :until,
          :count,
          :interval,
          :month_of_year,
          day:         [],
          day_of_week: [
            monday:    [],
            tuesday:   [],
            wednesday: [],
            thursday:  [],
            friday:    [],
            saturday:  [],
            sunday:    []
          ]
        ]
      end

      def update_schedule
        self.rule ||= "singular"
        self.interval ||= 1
        self.count ||= 0

        time = select_time

        time_string = time.strftime("%d-%m-%Y %I:%M %p")
        time = Time.zone.parse(time_string)

        @schedule = IceCube::Schedule.new(time)

        if self.rule && self.rule != "singular"

          self.interval = self.interval.present? ? self.interval.to_i : 1

          rule = IceCube::Rule.send(self.rule.to_s, self.interval)

          rule.until(self.until) if self.until

          rule.count(self.count.to_i) if self.count && self.count.to_i > 0

          if self.rule == "yearly"
            days = {}
            day_of_week.each do |weekday, value|
              days[weekday.to_sym] = value.reject(&:empty?).map { |x| x.to_i }
            end

            if month_of_year.present? && days.present?
              rule.day_of_week(days).month_of_year(month_of_year)
            elsif month_of_year.present?
              rule.day_of_week(days).month_of_year(month_of_year)
            end
          end

          if day
            days = day.reject(&:empty?)
            if self.rule == "weekly"
              days.each do |day|
                rule.day(day.to_sym)
              end
            elsif self.rule == "monthly"
              days = {}
              day_of_week.each do |weekday, value|
                days[weekday.to_sym] = value.reject(&:empty?).map(&:to_i)
              end
              rule.day_of_week(days)
            end
          end
          @schedule.add_recurrence_rule(rule)
        end
      end

      private

      def validate_day
        day.reject!(&:empty?)
        errors.add(:day, :empty) unless day.any?
      end

      def validate_day_of_week
        any = false
        day_of_week.each { |_key, value|
          value.reject!(&:empty?)
          if value.length > 0
            any = true
            break
          end
        }
        errors.add(:day_of_week, :empty) unless any
      end

      def select_time
        event_time = Time.zone.today.to_time(:utc)
        event_time = date.to_time(:utc) if date.present?
        event_time += time.seconds_since_midnight.seconds if time.present?
        # return event_time if created_at.blank?

        if rule == "yearly"
          return date.beginning_of_year + 1.year if date.present?

          # Not sure if these lines should be here for yearly and monthly.
          # Is there a valid case where date is not present? -nhennig 2021-02-05
          return 1.year.from_now.beginning_of_year
        end

        if rule == "month"
          return date.beginning_of_month + 1.month if date.present?

          return 1.month.from_now.beginning_of_month
        end

        event_time
      end
    end
  end
end
