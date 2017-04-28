module Jobs
  class RebakeCustomEmojiPosts < Jobs::Base
    sidekiq_options queue: 'special'

    def execute(args)
      name = args[:name]
      Post.where("raw LIKE '%:#{name}:%'").find_each { |post| post.rebake! }
    end
  end
end
