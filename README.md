# rent-control

### Redacted Output

```
Parsing document...Done.
Parsing LineItems...Done.
Parsed 200 items from 2022-03-01 to 2023-08-01.
Validating LineItems...Done.
Selecting months to calculate...
[WARNING] Removing payment from 2023-04-29 since it was for May
Calculating for months ["2022-08", "2022-09", "2022-10", "2022-11", "2022-12", "2023-01", "2023-02", "2023-03", "2023-04"]
Collecting total due...
  Collecting proportional-split charges... (i.e. rent)
  Collecting equal-split charges... (i.e. utilities, parking)
    accounting for A's guest months (Feb, Mar, Apr 2023)
Done.
{:a=>
  {"2022-08_rent"=>??,
   "2022-09_rent"=>??,
   ...
   "2022-08_parking"=>??,
   "2022-09_parking"=>??,
   ...
   "2022-08_util_charge"=>??,
   "2022-09_util_charge"=>??,
   ...}
 :j=>
  {"2022-08_rent"=>??,
   "2022-09_rent"=>??,
   ...
   "2022-08_parking"=>??,
   "2022-09_parking"=>??,
   ...
   "2022-08_util_charge"=>??,
   "2022-09_util_charge"=>??,
   ...}}
Validating charges...Done.

Calculating hypothetical charges
From 2022-08 through 2023-04
J owed: ??
A owed: ??
total: ??

Calculating actual paid
{:a=>
  {"2022-08_check_paid"=>??,
   "2022-09_check_paid"=>??,
   ...},
 :j=>
  {"2022-08_credit_card_paid"=>??,
   "2022-09_credit_card_paid"=>??,
   ...}}
Validating payments...Started with $0 balance, and ended with $0 balance...Done.

Calculating total payments
From 2022-08 through 2023-04
J paid: ??
A paid: ??
total: ??
J owed ?? but paid ??
  so J should venmo A ??
```
