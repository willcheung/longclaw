/*
function getnewURL(search,commentSelected,userSelected){
  //keep everything except for category and emails
  var finalURL = "";

  if(search.length==0){
    finalURL = encodeURI('?category='+commentSelected.join(',')+'&emails='+userSelected.join(','));
    return finalURL;
  }
  
  var params = search.split("&");
  var result = "";

  for(i=0; i<params.length; i++){
    var temp = params[i].split("=");
    if(temp[0].length>0 && temp[0]!=='category'&&temp[0]!='emails'){
      result += params[i] + "&";
    }
  }

  finalURL = encodeURI('?'+result+'category='+commentSelected.join(',')+'&emails='+userSelected.join(','));  
  // console.log(finalURL);
  return finalURL;

}


$(document).ready(function(){
  // $('.comment_category').chosen({ disable_search: false, allow_single_deselect: true});

  // $('.user_filter').chosen({disable_search: false, allow_single_deselect: true});

  var commentSelected = $('.comment_category').val();
  var userSelected = $('.user_filter').val();

  if(commentSelected==null)
  {
    commentSelected = [];
  }

  if(userSelected==null)
  {
    userSelected = [];
  }

  
  $('.comment_category').on('change',function(evt,params){  
    if(params["selected"]!=null)
    {
      commentSelected.push(params["selected"]);
    }
    else
    {
      var index = commentSelected.indexOf(params["deselected"]);
      if(index!=-1){
        commentSelected.splice(index, 1);
      }
    }

    var finalURL = getnewURL(window.location.search.substring(1),commentSelected,userSelected);
    window.location.replace(finalURL);
    
  });

   $('.user_filter').on('change',function(evt,params){
    if(params["selected"]!=null)
    {
      userSelected.push(params["selected"]);
    }
    else
    {
      var index = userSelected.indexOf(params["deselected"]);
      if(index!=-1){
        userSelected.splice(index, 1);
      }
    }
   
    var finalURL = getnewURL(window.location.search.substring(1),commentSelected,userSelected);
    window.location.replace(finalURL);
    
  });
});
*/



var g_minDate = 0;
var g_maxDate = 0;

var g_emails = [];
var g_categories = [];

function activityEmailFilter(value, emails){
   for (var i = 0; i < value.length; i++) {
    if(emails.indexOf(value[i])!=-1){
      return true;
    }    
  }
  return false;
}

function activityCategoryFilter(value, categories){
  if(categories.indexOf(value)!=-1)
    return true;

  return false;
}

function activityTimeFilter(value, minDate, maxDate){
  // console.log(value);
  // console.log(minDate);
  // console.log(maxDate);
   if(value>=minDate && value<=maxDate){
    return true;
   }
   return false;
}

function applyFilter(minDate, maxDate){

  activityTimeFilterReset();

  var monthIndex = 0;
  var i = 0;
  var monthShow = false;

  $('#vertical-timeline').children().each(function(){
    if( $(this).is("div") ){
      if( $(this).data('myvalue') == 'month'){
        monthIndex = i;
        monthShow = false;
        $(this).hide();
      }
      else
      {         
         $(this).children( ".vertical-timeline-content" ).each(function(){
          if( $(this).data('mytype')=='Note'){
            var cur_email = $(this).data('myemail');
            $(this).children(".chat-discussion").each(function(){
              var b_timeFilter = false;
              var b_categoryFilter = false;
              var b_emailFilter = false;

              // time filter
              if(g_minDate==0 && g_maxDate==0){
                b_timeFilter = true;
              }
              else{
                b_timeFilter = activityTimeFilter($(this).data('myvalue'), g_minDate, g_maxDate);
              }

              // category filter
              if(g_categories.length==0){
                b_categoryFilter = true;
              }
              else{
                b_categoryFilter = activityCategoryFilter('Note', g_categories);
              }

              //email filter
               if(g_emails.length==0){
                b_emailFilter = true;
              }
              else{
                b_emailFilter = activityEmailFilter(cur_email.split(','), g_emails);
              }


              // console.log('------------------');
              // console.log(b_timeFilter);
              // console.log(b_categoryFilter);
              // console.log(b_emailFilter);
              // console.log('------------------');

              if(b_timeFilter && b_categoryFilter & b_emailFilter){
                if(monthShow==false){
                  monthShow = true;
                  $('#vertical-timeline').children().eq(monthIndex).show();
                }
              }
              else{
                $(this).parent().parent().hide();
              }
            });

          }
          else if( $(this).data('mytype')=='Conversation'){
            var cur_email = $(this).data('myemail');
            var breakFlag = false;
            $(this).children(".chat-discussion").each(function(){
              breakFlag = false;
              $(this).children(".hidden-message-filter").each(function(){
                if(breakFlag!=true){
                  var b_timeFilter = false;
                  var b_categoryFilter = false;
                  var b_emailFilter = false;

                  // time filter
                  if(g_minDate==0 && g_maxDate==0){
                    b_timeFilter = true;
                  }
                  else{
                    b_timeFilter = activityTimeFilter($(this).data('myvalue'), g_minDate, g_maxDate);
                  }

                  // category filter
                  if(g_categories.length==0){
                    b_categoryFilter = true;
                  }
                  else{
                    b_categoryFilter = activityCategoryFilter('Conversation', g_categories);
                  }

                  //email filter
                  if(g_emails.length==0){
                    b_emailFilter = true;
                  }
                  else{
                    b_emailFilter = activityEmailFilter(cur_email.split(','), g_emails);
                  }


                  // console.log('------------------');
                  // console.log(b_timeFilter);
                  // console.log(b_categoryFilter);
                  // console.log(b_emailFilter);
                  // console.log('------------------');

                  if(b_timeFilter && b_categoryFilter & b_emailFilter){
                    if(monthShow==false){
                      monthShow = true;
                      $('#vertical-timeline').children().eq(monthIndex).show();
                      $(this).parent().parent().parent().show();
                      breakFlag = true;
                    }
                  }
                  else{
                    $(this).parent().parent().parent().hide();
                  }
                }
              });

            });

          }
          else if( $(this).data('mytype')=='Calendar' || $(this).data('mytype')=='Meeting' ){
            var cur_email = $(this).data('myemail');
            var breakFlag = false;
           
            $(this).children(".chat-discussion").each(function(){     
              var b_timeFilter = false;
              var b_categoryFilter = false;
              var b_emailFilter = false;

              // time filter
              if(g_minDate==0 && g_maxDate==0){
                b_timeFilter = true;
              }
              else{
                b_timeFilter = activityTimeFilter($(this).data('myvalue'), g_minDate, g_maxDate);
              }

              // category filter
              if(g_categories.length==0){
                b_categoryFilter = true;
              }
              else{
                b_categoryFilter = activityCategoryFilter('Meeting', g_categories);
              }

              //email filter
              if(g_emails.length==0){
                b_emailFilter = true;
              }
              else{
                b_emailFilter = activityEmailFilter(cur_email.split(','), g_emails);
              }


              // console.log('------------------');
              // console.log(b_timeFilter);
              // console.log(b_categoryFilter);
              // console.log(b_emailFilter);
              // console.log('------------------');

              if(b_timeFilter && b_categoryFilter & b_emailFilter){
                if(monthShow==false){
                  monthShow = true;
                  $('#vertical-timeline').children().eq(monthIndex).show();
                  $(this).parent().parent().parent().show();
                 
                }
              }
              else{
                $(this).parent().parent().hide();
              }            
            });
          }

        });
      }   
    }
    i++;
  });
}

function activityTimeFilterReset(){
  $('#vertical-timeline').children().show();
}

$(document).ready(function(){
  $('.comment_category').chosen({ disable_search: false, allow_single_deselect: true});

  $('.user_filter').chosen({disable_search: false, allow_single_deselect: true});  


  $('.comment_category').on('change',function(evt,params){  
    if(params["selected"]!=null){
      g_categories.push(params["selected"]);
    }
    else{
      var index = g_categories.indexOf(params["deselected"]);
      if(index!=-1){
        g_categories.splice(index, 1);
      }
    }
    console.log(g_categories);
    applyFilter();
  });

  $('.user_filter').on('change',function(evt,params){
    if(params["selected"]!=null){
      g_emails.push(params["selected"]);
    }
    else{
      var index = g_emails.indexOf(params["deselected"]);
      if(index!=-1){
        g_emails.splice(index, 1);
      }
    }
   
    applyFilter();
  });

});
