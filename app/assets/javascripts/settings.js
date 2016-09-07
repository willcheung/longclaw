$(document).ready(function() {
    $('#users-table').DataTable( {
        "scrollX": false,
        "responsive": true,
        "order": [[5, "desc"]],
        "bPaginate": false,
        "dom":' <"col-sm-4 row"f><"top">rt<"col-sm-5"l><"col-sm-5"p><"bottom"i><"clear">',
        "language": {
		      search: "_INPUT_",
		      searchPlaceholder: "Start typing to filter list..."
		    }
    } );
    
    $('input[type=search]').attr('size', '50');

    $('.salesforce_account_box').chosen({allow_single_deselect: true});

    $('.salesforce_account_box').on('change',function(evt,params){
        console.log($(this).attr('id'));
        console.log(params);   

        // $.ajax({url:'/notifications/'+$(this).attr('id')+'/update_is_complete'});

    if(params){
      $.ajax({url:'/update_salesforce/?id='+$(this).attr('id')+'&sid='+params["selected"]});
    }
    else{
      $.ajax({url:'/update_salesforce/?id='+$(this).attr('id')+'&sid= '});
    }

    });


    $(".salesforce-search").selectize({
      closeAfterSelect: true,
      valueField: 'id',
      labelField: 'name',
      searchField: ['name'],
      create: false,
      render: {
        item: function(item, escape) {
          return '<div>' +
              (item.name ? '<span class="name">' + escape(item.name) + '</span>' : '') +
              (item.account ? '<span class="account">' + escape(item.account) + '</span>' : '') +
          '</div>';
        },
        option: function(item, escape) {
          var label = item.name || item.account;
          var caption = item.name ? item.account : null;
          return '<div>' +
              '<span class="label">' + escape(label) + '</span>' +
              (caption ? '<span class="caption">' + escape(caption) + '</span>' : '') +
          '</div>';
        }
      },
      load: function (term, callback) {
        if (!term.length) return callback()
        // use # to search for projects by name
        // console.log(callback);
        $.getJSON( '/search/autocomplete_salesforce_account_name.json', { term: encodeURIComponent(term) } )
          .done( function (data) {
            // console.log(data);
            callback(data);
          })
          .fail( function () {
            console.log("fail");
            callback();
          })
        
      },
      onDropdownOpen: function ($dropdown) {
        // Manually prevent dropdown from opening when:
        // 1. There is no search term, or
        // 2. The search term does not begin with #
        // 3. At least one project has been selected already
        if (!this.lastQuery.length || this.items.length) {
          this.close();
        }
      },
      onBlur: function () {
        // Manually prevent input box from being cleared on blur
        this.setTextboxValue(this.lastQuery);
      }
  });

  $(".salesforce_account").hide();

  $('.contextsmith_account_box').chosen({allow_single_deselect: true, width: $('.contextsmith_account').width() + 'px'});  

} );