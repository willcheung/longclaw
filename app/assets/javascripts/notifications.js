// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.

function removeParam(search, keyword){
    if(search.length==0) return search;

    var params = search.split("&");
    var result = "";

    for(i=0; i<params.length; i++){
        var param = params[i].split("=");
        if(param[0].length>0 && param[0]!==keyword){
            result += params[i] + "&";
        }
    }

    if(result[result.length-1]==="&") return result.substring(0,result.length-1);
    else return result;

}

function newURL(search,selectType, newParam){
    // always remove & in the back or it will cause error
    var finalURL = "";
    var newsearch="";

    //always set to type=incomplete when search string is empty
    if(search.length==0){
        search = "?type=incomplete";
    }
    
    original = removeParam(search.substring(1), selectType);

    if(original.length==0){   
        newsearch = newParam;
    }
    else{
        if(newParam.length==0){
            // when user press X, newParam will be ""
            newsearch = original;
        }
        else{
            newsearch = original + "&" + newParam;
        }
    }

    if(newsearch.length==0){
        finalURL = "/notifications";
    }
    else{
        finalURL = "/notifications/?"+newsearch;
    }

    // console.log(finalURL);
    window.location.replace(finalURL);

}

$('.is_complete_box').chosen({ disable_search: true, allow_single_deselect: true});

$('.filter_section').hover(function(){
    $('.chosen-container-single').css('cursor', 'pointer');
    $('.chosen-single').css('cursor', 'pointer'); 
});


$('.is_complete_box').on('change',function(evt,params){

    var taskType="";

    if(params){
        switch(params["selected"]){
            case "1":
                taskType = "type=incomplete";
                break;
            case "2":
                taskType = "type=complete";
                break;
            default:
                break;
        }
    }
    else{
        taskType = "type=all";
    }

    newURL(window.location.search,"type", taskType);
        
});

$('.assignee_box').chosen({disable_search: true, allow_single_deselect: true});

$('.assignee_box').on('change',function(evt,params){

    var taskType="";

    if(params){
        switch(params["selected"]){
            case "1":
                taskType = "assignee=me";
                break;
            case "2":
                taskType = "assignee=none";
                break;
            default:
                break;
        }
    }

    newURL(window.location.search,"assignee", taskType);
        
});


$('.due_date_box').chosen({ disable_search: true, allow_single_deselect: true});

$('.due_date_box').on('change',function(evt,params){

    var taskType="";

    if(params){
        switch(params["selected"]){
            case "1":
                taskType = "duedate=oneweek";
                break;
            case "2":
                taskType = "duedate=none";
                break;
            case "3":
                taskType = "duedate=overdue";
            default:
                break;
        }
    }

    newURL(window.location.search,"duedate", taskType);
      
});

$('.project_box').chosen({allow_single_deselect: true});

$('.project_box').on('change',function(evt,params){

    var taskType="";

    if(params){
        taskType = "projectid="+params["selected"];
    }

    newURL(window.location.search,"projectid", taskType);
      
});

