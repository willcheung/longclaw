class CommentsController < ApplicationController
  before_action :set_comment, only: [:edit, :update, :destroy]

  # GET /comments
  # GET /comments.json
  def index
    @comments = Comment.all
  end

  # GET /comments/1
  # GET /comments/1.json
  def show
  end

  # GET /comments/new
  def new
    @comment = Comment.new
  end

  # GET /comments/1/edit
  def edit
  end

  # POST /comments
  # POST /comments.json
  def create
  	if params[:activity_id]
  		@activity = Activity.find_by_id(params[:activity_id])
  		@comment = @activity.comments.new(comment_params.merge(:user_id => current_user.id))
    end

    respond_to do |format|
      if @comment.save
        #format.html { redirect_to @comment, notice: 'Comment was successfully created.' }
        format.json { render action: 'show', status: :created, location: @comment }
        format.js
      else
        #format.html { render action: 'new' }
        format.json { render json: @comment.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /comments/1
  # PATCH/PUT /comments/1.json
  def update
    respond_to do |format|
      if @comment.update(comment_params)
        #format.html { redirect_to @comment, notice: 'Comment was successfully updated.' }
        format.json { respond_with_bip(@comment) }
        format.js
      else
        #format.html { render action: 'edit' }
        format.json { respond_with_bip(@comment) }
      end
    end
  end

  # DELETE /comments/1
  # DELETE /comments/1.json
  def destroy
    project = @comment.commentable.project
    @comment.destroy
    respond_to do |format|
      format.html { redirect_to project_url(project) }
      format.json { head :no_content }
      format.js
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_comment
      @comment = Comment.find(params[:id])
      @comment = nil unless @comment.commentable.project.account.organization == current_user.organization
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def comment_params
      params.require(:comment).permit(:comment, :user_id, :commentable_type, :commentable_id, :title, :commentable_uuid, :is_public)
    end
end
