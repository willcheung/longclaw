//= require datepicker/bootstrap-datepicker.js

var elem = document.querySelector('.billable_switch');
var switchery = new Switchery(elem, { color: '#1AB394' });

$('.start_date_datepicker').datepicker({
  keyboardNavigation: false,
  todayHighlight: true,
  autoclose: true
});
