class DeletePlannedPost < RubyLLM::Tool
  description "Permanently delete a planned post by ID. Use as an alternative to update — " \
              "delete a single-photo post and replace it with a new carousel post."

  parameter :id,
    type: :integer,
    description: "The planned post ID to delete"

  def execute(id:)
    post = PlannedPost.find_by(id: id)
    return { error: "Planned post ##{id} not found" } unless post

    post.destroy!
    { deleted: true, id: id }
  end
end
