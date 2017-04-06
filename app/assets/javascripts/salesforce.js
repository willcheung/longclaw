// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.

jQuery(document).ready(function($) {
});

function toggleSection(toggleSectionParentDOMObj) {
    if (toggleSectionParentDOMObj) {
        toggleSectionParentDOMObj.find(".toggle-icon").toggleClass("fa-caret-right fa-caret-down");
        toggleSectionParentDOMObj.next().next().toggle(400);
    }
};