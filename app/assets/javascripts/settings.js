//= require highcharts-sparkline/highcharts-sparkline.js
$('[data-toggle="tooltip"]').tooltip();

$(document).ready(function() {
    // TODO: completely remove below commented code if confirm commenting it out doesn't break anything!
    // $('.salesforce_account_box').chosen({allow_single_deselect: true});

    // $('.salesforce_account_box').on('change',function(evt,params){
    //     console.log($(this).attr('id'));
    //     console.log(params);   

    //     // $.ajax({url:'/notifications/'+$(this).attr('id')+'/update_is_complete'});

    // if(params){
    //   $.ajax({url:'/update_salesforce/?id='+$(this).attr('id')+'&sid='+params["selected"]});
    // }
    // else{
    //   $.ajax({url:'/update_salesforce/?id='+$(this).attr('id')+'&sid= '});
    // }

    // });

    ////////////////////////////////////////
    // ../settings/salesforce_accounts
    ////////////////////////////////////////
    $("#salesforce-account-search").selectize({
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

    $('.sfdc-refresh').click(function(){
        var self = $(this);
        var entity_type, entity_type_btn_str;
        var buttonTxtStr = self.attr("btnLabel");

        if ($(this).attr("id").includes("salesforce-acc-refresh")) {
            entity_type = "accounts";
        }
        else if ($(this).attr("id").includes("salesforce-opp-refresh")) {
            entity_type = "opportunities";
        }
        else if ($(this).attr("id").includes("salesforce-con-refresh")) {
            entity_type = "contacts";
        }

        // console.log("$(this).attr('id'): " + self.attr("id"));
        
        $.ajax('/salesforce/refresh/' + entity_type, {
            async: true,
            method: "POST",
            beforeSend: function () {
                $("#" + self.attr("id") + " .fa.fa-refresh").addClass('fa-spin');
            },
            success: function() {
                self.addClass('success-btn-highlight');
                self.html("✓ " + buttonTxtStr);
            },
            error: function(data) {
                var res = JSON.parse(data.responseText);
                self.addClass('error-btn-highlight');
                alert(buttonTxtStr + " error!\n\n" + res.error);
            },
            statusCode: {
                500: function() {
                    self.css("margin-left","60px");
                    self.html("<i class='fa fa-exclamation'></i> Salesforce query error");
                },
                503: function() {
                    self.css("margin-left","30px");
                    self.html("<i class='fa fa-exclamation'></i> Salesforce connection error");
                },
            },
            complete: function() {
                $("#" + self.attr("id") + " .fa.fa-refresh").removeClass('fa-spin');
                location.reload();
            }
        });
    });

    ////////////////////////////////////////
    // ../settings/salesforce_opportunities
    ////////////////////////////////////////
    $("#salesforce-opportunity-search").selectize({
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
          $.getJSON( '/search/autocomplete_salesforce_opportunity_name.json', { term: encodeURIComponent(term) } )
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
    $(".contextsmith_project_box").hide();


    $('.contextsmith_account_box').chosen({allow_single_deselect: true, width: $('.contextsmith_account').width() + 'px'}); 
    $('.basecamp2_account_box').chosen({allow_single_deselect: true, width: $('.contextsmith_account').width() + 'px'});
    $('.contextsmith_project_box').chosen({allow_single_deselect: true, width: $('.contextsmith_account').width() + 'px'});     


    ////////////////////////////////////////
    // ../settings/salesforce_activities
    ////////////////////////////////////////
    $('#salesforce-activity-save-entity-predicate-btn,#salesforce-activity-save-activityhistory-predicate-btn').click(function(){
        var self = $(this);
        var type;

        if (self.attr("id").includes("salesforce-activity-save-entity-predicate-btn")) {
            type = "entity";
        }
        else {
            type = "activityhistory";
        }

        var custom_config_id = document.getElementById("salesforce-activity-" + type + "-predicate-customconfig-id").value.trim();
        var config_type = "/settings/salesforce_activities#salesforce-activity-" + type + "-predicate-textarea";
        var predicate = document.getElementById("salesforce-activity-" + type + "-predicate-textarea").value.trim();

        var requestURL = encodeURI( "/custom_configurations/" + custom_config_id);
        $.ajax(requestURL, {
            async: true,
            method: "PATCH",
            data: { "custom_configuration[config_type]": config_type,  "custom_configuration[config_value]": predicate },
            beforeSend: function () {
                self.prop("disabled",true);
                self.html("<i class='fa fa-refresh fa-spin'></i>");
            },
            // TODO: didn't handle error!!
            complete: function() {
                self.html("<i class='fa fa-floppy-o'></i>");
                self.addClass("green-fadeto-grey");  // 3s
                setTimeout(function() { self.removeClass("green-fadeto-grey")}, 3000); // remove to restore mouseover effect
            }
        });
    });

    $('#salesforce-activity-refresh').click(function(){
        var self = $(this);
        var buttonTxtStr = self.attr("btnLabel");

        $.ajax("/salesforce/refresh/activities", {
            async: true,
            method: "POST",
            data: { entity_pred: document.getElementById("salesforce-activity-entity-predicate-textarea").value.trim(), activityhistory_pred: document.getElementById("salesforce-activity-activityhistory-predicate-textarea").value.trim() },
            beforeSend: function () {
                self.css("pointer-events", "none");
                self.prop("disabled",true);
                self.removeClass('success-btn-highlight error-btn-highlight');
                self.addClass('btn-primary btn-outline');
                self.html("<i class='fa fa-refresh fa-spin'></i> "+buttonTxtStr);
            },
            success: function() {
                self.addClass('success-btn-highlight');
                self.html("✓ "+buttonTxtStr);
            },
            error: function(data) {
                var res = JSON.parse(data.responseText);
                self.addClass('error-btn-highlight');
                alert(buttonTxtStr+" error!\n\n" + res.error);
            },
            statusCode: {
                500: function() {
                    self.html("<i class='fa fa-exclamation'></i> Salesforce query error");
                },
                503: function() {
                    self.html("<i class='fa fa-exclamation'></i> Salesforce connection error");
                },
            },
            complete: function() {
                self.css("pointer-events", "auto");
                self.prop("disabled",false);
                self.removeClass('btn-primary btn-outline');
            }
        });
    });

    $('#salesforce-activity-cs-export').click(function(){
        var self = $(this);
        var buttonTxtStr = self.attr("btnLabel");

        $.ajax("/salesforce_activityhistory_update", {
            async: true,
            method: "POST",
            data: {},
            beforeSend: function () {
                self.css("pointer-events", "none");
                self.prop("disabled",true);
                self.removeClass('success-btn-highlight error-btn-highlight');
                self.addClass('btn-primary btn-outline');
                self.html("<i class='fa fa-refresh fa-spin'></i> "+buttonTxtStr);
            },
            success: function() {
                self.addClass('success-btn-highlight');
                self.html("✓ "+buttonTxtStr);
            },
            error: function(data) {
                var res = JSON.parse(data.responseText);
                self.addClass('error-btn-highlight');
                alert(buttonTxtStr+" error!\n\n" + res.error);
            },
            statusCode: {
                500: function() {
                    self.html("<i class='fa fa-exclamation'></i> Salesforce update error");
                },
                503: function() {
                    self.html("<i class='fa fa-exclamation'></i> Salesforce connection error");
                },
            },
            complete: function() {
                self.css("pointer-events", "auto");
                self.prop("disabled",false);
                self.removeClass('btn-primary btn-outline');
            }
        });
    });

    ////////////////////////////////////////
    // ../settings/salesforce_fields
    ////////////////////////////////////////
    $('#salesforce-fields-refresh-accounts-btn,#salesforce-fields-refresh-projects-btn').click(function() {
        var self = $(this);
        var entity_type, entity_type_btn_str;

        if (self.attr("id").includes("salesforce-fields-refresh-accounts-btn")) {
            entity_type = "accounts";
            entity_type_btn_str = "Accounts";
        } 
        else {
            entity_type = "projects";
            entity_type_btn_str = "Streams";
        }

        $.ajax('/salesforce_fields_refresh?entity_type=' + entity_type, {
            async: true,
            method: "POST",
            data: "",
            beforeSend: function () {
                self.css("pointer-events", "none");
                self.css("margin-left","0px");
                self.removeClass('success-btn-highlight error-btn-highlight');
                self.addClass('btn-primary btn-outline');
                self.html("<i class='fa fa-refresh fa-spin'></i> Refresh ContextSmith " + entity_type_btn_str);
            },
            success: function() {
                self.addClass('success-btn-highlight');
                self.html("✓ Refresh ContextSmith " + entity_type_btn_str);
            },
            error: function(data) {
                var res = JSON.parse(data.responseText);
                self.addClass('error-btn-highlight');
                alert("Refresh ContextSmith " + entity_type_btn_str + " error!\n\n" + res.error);
            },
            statusCode: {
                500: function() {
                    self.css("margin-left","60px");
                    self.html("<i class='fa fa-exclamation'></i> Salesforce query error");
                },
                503: function() {
                    self.css("margin-left","30px");
                    self.html("<i class='fa fa-exclamation'></i> Salesforce connection error");
                },
            },
            complete: function() {
                self.css("pointer-events", "auto");
                self.removeClass('btn-primary btn-outline');
            }
        });
    });

    $('.salesforce-account-field-name,.salesforce-opportunity-field-name').change(function() {
        var selectorStr, entity_type_btn_str;
        if ($(this).attr("class").includes("salesforce-account-field-name")) {
          selectorStr = "#salesforce-fields-refresh-accounts-btn";
          entity_type_btn_str = "Accounts";
        } 
        else {
          selectorStr = "#salesforce-fields-refresh-projects-btn";
          entity_type_btn_str = "Streams";
        }

        // Reset button style to initial state
        $(selectorStr).css("margin-left","0px")
        $(selectorStr).removeClass('success-btn-highlight error-btn-highlight');
        $(selectorStr).addClass('btn-primary btn-outline');
        $(selectorStr).html("<i class='fa fa-refresh'></i> Refresh ContextSmith " + entity_type_btn_str)
        
        var exclamation_triangle_warning = document.getElementById("exclamation-triangle-warning-cfid"+ $(this).attr("cf_id"));
        if (exclamation_triangle_warning != undefined)
            exclamation_triangle_warning.style.display = "none"; // remove warning
    });

} );