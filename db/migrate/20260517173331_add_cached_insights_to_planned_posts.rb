class AddCachedInsightsToPlannedPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :planned_posts, :cached_insights, :json
  end
end
