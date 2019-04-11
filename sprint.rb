require 'active_record'


class Sprint < ActiveRecord::Base
  self.primary_key = 'started_at'

  def started_at_dt
    DateTime.parse(started_at)
  end
end
