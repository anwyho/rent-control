#! /usr/bin/env ruby
# typed: true
# frozen_string_literal: true

require 'nokogiri'
require 'open-uri'
require 'pry'
require 'sorbet-runtime'
extend T::Sig

RENT_DUMP_FILENAME = './tmp/2022-03-01_2023-04-01'

class LineItem < T::Struct
  extend T::Sig

  class Activity < T::Enum
    extend T::Helpers
    enums do
      Check = new "Check"
      CreditCard = new "Credit Card Payment"
      Rent = new "Monthly Apartment Rent"
      Parking = new "Monthly Reserved Parking"
      ParkingConcession = new "Monthly Parking Discount"
      RubsBillingFee = new "RUBS Billing Fee"
      RubsGas = new "RUBS Gas/Central Boiler"
      RubsPest = new "RUBS Pest"
      RubsSewer = new "RUBS Sewer"
      RubsTrash = new "RUBS Trash"
      RubsWater = new "RUBS Water"
      # Package storage
      Misc = new "Other Miscel. Income"
    end

    Payment = T.type_alias { T.any Check, CreditCard }
    Utilities = T.type_alias { 
      T.any RubsBillingFee, RubsGas, RubsPest, RubsSewer, RubsTrash, RubsWater, Misc
    }
  end

  const :date, Date
  const :activity, Activity
  const :description, String
  const :amount, Numeric
  const :balance, Numeric

  sig { params(row: T::Array[String], date: Date).returns(LineItem) }
  def self.from_row(row, date:)
    activity, description, amount_s, balance_s = row
    new(
      activity: Activity.deserialize(activity),
      description: T.must(description), 
      amount:   T.must(amount_s).gsub(/[^-\d\.]/, '').to_f,
      balance: T.must(balance_s).gsub(/[^-\d\.]/, '').to_f,
      date: date,
    )
  end
end

print 'Parsing document...'
# Makes Sorbet happy and is also kinda funny
doc = T.unsafe(Object.const_get :Nokogiri)::HTML File.read RENT_DUMP_FILENAME
puts 'Done.'


# Example `tr`s: 
  # 3/22/2023
  # Monthly Parking Discount	March Credit	-$30.65	-$736.75
  # 3/1/2023
  # RUBS Water	WATER	$45.87	-$706.10
print 'Parsing LineItems...'
items = T.let([], T::Array[LineItem])
first_date = T.let(nil, T.nilable(Date))
current_date = T.let(nil, T.nilable(Date))
# <tr> elements
rows = doc.search('tbody').first.children.select { |c| c.name != 'text' }
rows.map { |tr| 
  row = tr.children.select { |c| c.name != 'text' }.map(&:children).map(&:text)
  case row.length
  when 1
    # ["7/6/2022"]
    month, day, year = row.first.split('/').map(&:to_i)
    date = Date.new year, month, day
    first_date ||= date
    current_date = date
  when 4
    # ["Credit Card Payment", "Credit Card", "-$165.45", "$0.00"]
    # `unshift` to sort items by ascending date
    items.unshift LineItem.from_row row, date: T.must(current_date)
  else raise StandardError, row
  end
}
puts 'Done.'
puts "Parsed #{items.count} items from #{current_date} to #{first_date}."


print 'Validating LineItems...'
current_item, *rest = items
raise if current_item.nil? || rest.nil? # for Sorbet flow-sensitivity
rest.each do |next_item| 
  new_balance = (current_item.balance + next_item.amount).round 2
  if new_balance == next_item.balance
    current_item = next_item
  else raise StandardError, [current_item.date, new_balance, next_item.balance]
  end
end
puts 'Done.'


# TODO: hypothetical Josh-Anthony payment
# TODO: actual Josh-Anthony payment
# TODO: how to validate it's correct
# TODO: future things
