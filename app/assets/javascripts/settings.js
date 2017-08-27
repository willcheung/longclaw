//= require highcharts-sparkline/highcharts-sparkline.js
$('[data-toggle="tooltip"]').tooltip();

$(document).ready(function() {
    // Disable the submit button after submitting a form
    $("#search-form").submit(function () {
        $("#search-form .btn").attr("disabled", true);
        return true;
    });

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
        sortField: [
            {
                field: 'name',
                direction: 'asc'
            },
            {
                field: '$score'
            }
        ],
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

        if ($(this).attr("id").includes("salesforce-accounts-acc-refresh")) {  //clicked on 'Refresh Accounts'
            entity_type = "account";
        }
        else if ($(this).attr("id").includes("salesforce-accounts-opp-refresh")) {  //clicked on 'Refresh Opportunities'
            entity_type = "project";
        }
        else {
            return;
        }

        // console.log("$(this).attr('id'): " + self.attr("id"));
        
        $.ajax('/salesforce/import/'+entity_type, {
            async: true,
            method: "POST",
            // data: { "entity_type": entity_type },
            beforeSend: function () {
                self.css("pointer-events", "none");
                $("#" + self.attr("id") + " .fa.fa-refresh").addClass('fa-spin');
            },
            success: function() {
                self.addClass('success-btn-highlight');
                self.html("✓ " + buttonTxtStr);
            },
            error: function(data) {
                var res = JSON.parse(data.responseText);
                self.addClass('error-btn-highlight');
                console.log(buttonTxtStr + " error\n\n" + "-".repeat(50) + "\nStatus:\n" + "-".repeat(50) + "\n" + res.error);
                alert("There was a " + buttonTxtStr + " error, but it has been logged and our team will get right on it shortly to resolve it!");
            },
            statusCode: {
                500: function() {
                    //self.css("margin-left","0px");
                    self.html("<i class='fa fa-exclamation'></i> Salesforce query error");
                },
                503: function() {
                    //self.css("margin-left","0px");
                    self.html("<i class='fa fa-exclamation'></i> Salesforce connection error");
                },
            },
            complete: function() {
                self.css("pointer-events", "auto");
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
        sortField: [
            {
                field: 'name',
                direction: 'asc'
            },
            { 
                field: '$score' 
            }
        ],
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

        if (self.attr("id").includes("entity")) {
            type = "entity";
        }
        else if (self.attr("id").includes("activityhistory")) {
            type = "activityhistory";
        }
        else {
            return;
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
                self.prop("disabled", true);
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

    $('#salesforce-activities-sync').click(function(){
        var self = $(this);
        var error500_msg;
        var requestURL;
        var request_data = {};
        var buttonTxtStr = self.attr("btnLabel");

        if (self.attr("id").includes("salesforce-activities-sync")) {
            error500_msg = "Sync activities error";
            requestURL = "/salesforce/sync";
            request_data = { "entity_type": "activity", entity_pred: document.getElementById("salesforce-activity-entity-predicate-textarea").value.trim(), activityhistory_pred: document.getElementById("salesforce-activity-activityhistory-predicate-textarea").value.trim() };
        }
        else {
            error500_msg = "Sync activities error";
            requestURL = "/salesforce/sync";
        }

        $.ajax(requestURL, {
            async: true,
            method: "POST",
            data: request_data,
            beforeSend: function () {
                self.css("pointer-events", "none");
                self.prop("disabled", true);
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
                console.log(buttonTxtStr + " error\n\n" + "-".repeat(50) + "\nStatus:\n" + "-".repeat(50) + "\n" + res.error);
                alert("There was a " + buttonTxtStr + " error, but it has been logged and our team will get right on it shortly to resolve it!");
            },
            statusCode: {
                500: function() {
                    self.html("<i class='fa fa-exclamation'></i> " + error500_msg);
                },
                503: function() {
                    self.html("<i class='fa fa-exclamation'></i> Salesforce connection error");
                },
            },
            complete: function() {
                self.css("pointer-events", "auto");
                self.prop("disabled", false);
                self.removeClass('btn-primary btn-outline');
            }
        });
    });

    ////////////////////////////////////////
    // ../settings/salesforce_fields
    ////////////////////////////////////////
    $('#salesforce-fields-refresh-account-btn,#salesforce-fields-refresh-opportunity-btn').click(function() {
        var self = $(this);
        var entity_type;
        var buttonTxtStr = self.attr("btnLabel");

        if (self.attr("id").includes("account")) {
            entity_type = "account";
        } 
        else if (self.attr("id").includes("opportunity")) {
            entity_type = "project";
        } 
        else {
            return;
        }

        $.ajax('/salesforce/import/'+entity_type, {
            async: true,
            method: "POST",
            // data: { "entity_type": entity_type },
            beforeSend: function () {
                self.css("pointer-events", "none");
                self.css("margin-left","0px");
                self.removeClass('success-btn-highlight error-btn-highlight');
                self.addClass('btn-primary btn-outline');
                self.html("<i class='fa fa-refresh fa-spin'></i> " + buttonTxtStr);
            },
            success: function() {
                self.addClass('success-btn-highlight');
                self.html("✓ " + buttonTxtStr);
            },
            error: function(data) {
                var res = JSON.parse(data.responseText);
                self.addClass('error-btn-highlight');
                console.log(buttonTxtStr + " error\n\n" + "-".repeat(50) + "\nStatus:\n" + "-".repeat(50) + "\n" + res.error);
                alert("There was a " + buttonTxtStr + " error, but it has been logged and our team will get right on it shortly to resolve it!");
            },
            statusCode: {
                500: function() {
                    self.css("margin-left","-20px");
                    self.html("<i class='fa fa-exclamation'></i> Salesforce query error");
                },
                503: function() {
                    self.css("margin-left","-50px");
                    self.html("<i class='fa fa-exclamation'></i> Salesforce connection error");
                },
            },
            complete: function() {
                self.css("pointer-events", "auto");
                self.removeClass('btn-primary btn-outline');
            }
        });
    });

    $('#salesforce-standard-fields-sync-contacts-btn').click(function() {
        var self = $(this);
        var entity_type;
        var buttonTxtStr = self.attr("btnLabel");

        // if (self.attr("id").includes("accounts")) {
        //     entity_type = "accounts";
        // } 
        // else if (self.attr("id").includes("projects")) {
        //     entity_type = "projects";
        // } 
        // else {
            entity_type = "contacts";
        // }

        $.ajax('/salesforce/sync', {
            async: true,
            method: "POST",
            data: { "entity_type": entity_type },
            beforeSend: function () {
                self.css("pointer-events", "none");
                self.css("margin-left","0px");
                self.removeClass('success-btn-highlight error-btn-highlight');
                self.addClass('btn-primary btn-outline');
                self.html("<i class='fa fa-refresh fa-spin'></i> " + buttonTxtStr);
            },
            success: function() {
                self.addClass('success-btn-highlight');
                self.html("✓ " + buttonTxtStr);
            },
            error: function(data) {
                var res = JSON.parse(data.responseText);
                self.addClass('error-btn-highlight');
                console.log(buttonTxtStr + " error\n\n" + "-".repeat(50) + "\nStatus:\n" + "-".repeat(50) + "\n" + res.error);
                alert("There was a " + buttonTxtStr + " error, but it has been logged and our team will get right on it shortly to resolve it!");
            },
            statusCode: {
                500: function() {
                    self.css("margin-left","-45px");
                    self.html("<i class='fa fa-exclamation'></i> Salesforce query error");
                },
                503: function() {
                    self.css("margin-left","-75px");
                    self.html("<i class='fa fa-exclamation'></i> Salesforce connection error");
                },
            },
            complete: function() {
                self.css("pointer-events", "auto");
                self.removeClass('btn-primary btn-outline');
            }
        });
    });

    $('.salesforce-account-field-name,.salesforce-opportunity-field-name,.salesforce-contact-field-name').change(function() {
        var selectorStr, entity_type_btn_str;
        var field_type = ($(this).attr("f_id") != undefined) ? "standard" : "custom";

        if ($(this).attr("class").includes("salesforce-account-field-name")) {
            selectorStr = "#salesforce-"+field_type+"-fields-refresh-accounts-btn";
            entity_type_btn_str = "Refresh Accounts";
        } 
        else if ($(this).attr("class").includes("salesforce-opportunity-field-name")) {
            selectorStr = "#salesforce-"+field_type+"-fields-refresh-projects-btn";
            entity_type_btn_str = "Refresh Opportunities";
        } 
        else {
            selectorStr = "#salesforce-standard-fields-sync-contacts-btn";
            entity_type_btn_str = "Sync Contacts";
        }

        // Reset button style to initial state
        $(selectorStr).css("margin-left","0px")
        $(selectorStr).removeClass('success-btn-highlight error-btn-highlight');
        $(selectorStr).addClass('btn-primary btn-outline');
        $(selectorStr).html("<i class='fa fa-refresh'></i> "+entity_type_btn_str);
        
        var exclamation_triangle_warning = field_type == "standard" ? document.getElementById("exclamation-triangle-warning-fid"+$(this).attr("f_id")) : document.getElementById("exclamation-triangle-warning-cfid"+$(this).attr("cf_id"));
        if (exclamation_triangle_warning != undefined)
            exclamation_triangle_warning.style.display = "none"; // remove warning
    });
} );