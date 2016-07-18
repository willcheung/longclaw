
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
  $('.comment_category').chosen({ disable_search: false, allow_single_deselect: true});

  $('.user_filter').chosen({disable_search: false, allow_single_deselect: true});

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