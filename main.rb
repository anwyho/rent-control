#! /usr/bin/env ruby
# typed: true
# frozen_string_literal: true

require 'nokogiri'
require 'open-uri'
require 'pry'
require 'sorbet-runtime'
extend T::Sig

# TODO: make a folder tmp, 
#   add this file, 
#   and copy the HTML element from site that contains the <table> element
RENT_DUMP_FILENAME = './tmp/2022-03-01_2023-08-01'

class LineItem < T::Struct
  extend T::Sig

  class Activity < T::Enum
    extend T::Helpers
    enums do
      Check = new "Check" # A's form of payment
      CreditCard = new "Credit Card Payment" # J's form of payment
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

    PAYMENT_TYPES = T.let([Check, CreditCard], [Check, CreditCard])
    OWED_TYPES = T.let([Rent, Parking, ParkingConcession, RubsBillingFee, RubsGas, RubsPest, RubsSewer, RubsTrash, RubsWater, Misc], [Rent, Parking, ParkingConcession, RubsBillingFee, RubsGas, RubsPest, RubsSewer, RubsTrash, RubsWater, Misc])
    EQUAL_SPLIT_TYPES = T.let([Parking, ParkingConcession, RubsBillingFee, RubsGas, RubsPest, RubsSewer, RubsTrash, RubsWater, Misc], [Parking, ParkingConcession, RubsBillingFee, RubsGas, RubsPest, RubsSewer, RubsTrash, RubsWater, Misc])
    PROPORTIONAL_SPLIT_TYPES = T.let([Rent], [Rent])
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

  sig { returns(String) }
  def as_row
    "#{date},#{amount},#{balance},#{activity.serialize},#{description}"
  end
end


# PARSING & VALIDATION

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


# SELECTION

puts 'Selecting months to calculate...'
items_by_month = items.group_by { |item| "#{item.date.year}-#{item.date.month.to_s.rjust(2, '0')}" }
months_due = items_by_month.select { |month, _items| month >= '2022-08' && month <= '2023-04' }
if months_due.keys.last == '2023-04'
  puts '[WARNING] Removing payment from 2023-04-29 since it was for May'
  months_due.values.last.reject! { |item| item.date == Date.new(2023, 4, 29) }
end
puts "Calculating for months #{months_due.keys}"


# CHARGES

sig { params(items: T::Array[LineItem], types: T::Array[LineItem::Activity]).returns(Numeric) }
def amount_for_type(items, types)
  selected_items = items.select { |item| types.include?(item.activity) }
  # puts items.map(&:as_row)
  # puts
  # puts selected_items.map(&:as_row)
  selected_items.sum(&:amount)
end

puts 'Collecting total due...'
charges = {a: {}, j: {}}

puts '  Collecting proportional-split charges... (i.e. rent)'
# J pays 
J_PROPORTION = 0.47651 # % of rent based on sqft of living space
months_due.each do |month, items|
  amount_owed = amount_for_type(items, LineItem::Activity::PROPORTIONAL_SPLIT_TYPES)
  key = "#{month}_rent"
  charges[:j][key] = amount_owed * J_PROPORTION
  charges[:a][key] = amount_owed - charges[:j][key]
end

puts '  Collecting equal-split charges... (i.e. utilities, parking)'
puts '    accounting for A\'s guest months (Feb, Mar, Apr 2023)'
# parking
parking_types = [LineItem::Activity::Parking, LineItem::Activity::ParkingConcession]
months_due.each do |month, items|
  amount_owed = amount_for_type(items, parking_types)
  key = "#{month}_parking"
  charges[:j][key] = amount_owed / 2
  charges[:a][key] = amount_owed - charges[:j][key]
end
# utils
months_due.each do |month, items|
  amount_owed = amount_for_type(items, LineItem::Activity::EQUAL_SPLIT_TYPES - parking_types)
  key = "#{month}_util_charge"
  # for when A had guest
  if ['2023-02', '2023-03', '2023-04'].include?(month)
    charges[:j][key] = amount_owed / 3
    charges[:a][key] = amount_owed - charges[:j][key]
  else
    charges[:j][key] = amount_owed / 2
    charges[:a][key] = amount_owed - charges[:j][key]
  end
end
puts 'Done.'

pp charges

print 'Validating charges...'
total_owed = charges[:j].values.sum + charges[:a].values.sum
calculated_owed = amount_for_type(months_due.values.flatten, LineItem::Activity::OWED_TYPES)
raise StandardError, [total_owed, calculated_owed] unless (total_owed - calculated_owed).abs < 0.0001
puts 'Done.'
puts

puts 'Calculating hypothetical charges'
j_owed = charges[:j].values.sum
a_owed = charges[:a].values.sum
puts "From #{months_due.keys.first} through #{months_due.keys.last}"
puts "J owed: #{j_owed}"
puts "A owed: #{a_owed}"
puts "total: #{total_owed}"
puts 

# PAYMENTs

puts 'Calculating actual paid'
payments = {a: {}, j: {}}

months_due.each do |month, items| 
  # J pays with credit card
  amount_paid = amount_for_type(items, [LineItem::Activity::CreditCard]).abs
  key = "#{month}_credit_card_paid"
  payments[:j][key] = amount_paid
  
  # A pays with check
  amount_paid = amount_for_type(items, [LineItem::Activity::Check]).abs
  key = "#{month}_check_paid"
  payments[:a][key] = amount_paid
end

pp payments

print 'Validating payments...'
total_paid = payments[:j].values.sum + payments[:a].values.sum
calculated_paid = amount_for_type(months_due.values.flatten, LineItem::Activity::PAYMENT_TYPES)
raise StandardError, [total_paid, calculated_paid] unless (total_paid.abs - calculated_paid.abs).abs < 0.0001

# had a $0 balance to start out and ended on $0 balance
if months_due.values.first.first.amount == months_due.values.first.first.balance && months_due.values.last.last.balance == 0
  print 'Started with $0 balance, and ended with $0 balance...'
  raise StandardError, [total_paid, total_owed] unless (total_paid.abs - total_owed.abs).abs < 0.0001
end
puts 'Done.'
puts

puts 'Calculating total payments'
puts "From #{months_due.keys.first} through #{months_due.keys.last}"
j_paid = payments[:j].values.sum
a_paid = payments[:a].values.sum
puts "J paid: #{j_paid}"
puts "A paid: #{a_paid}"
puts "total: #{total_paid}"
puts 


# DISCREPANCIES
puts "J owed #{j_owed.round(3)} but paid #{j_paid.round(3)}"
puts "  so J should venmo A #{(j_owed - j_paid).round(3)}"
