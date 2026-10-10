# frozen_string_literal: true

require "rails_helper"

# The SSE endpoints stream through the same services as the web
# (ChannelContents::Generation, Streams::RagChat, Streams::ChannelProposal),
# so the AI services are stubbed and the event sequence is checked.
RSpec.describe "App API streaming", type: :request do
  let!(:user) { api_user }
  let(:token) { api_token_for(user) }
  let!(:channel) { user.channels.create!(name: "News", language: "en", prompt: "x") }
  let!(:event) { user.sources.manual.first.events.create!(external_id: "m1", content: "Bitcoin news", published_at: 1.hour.ago) }
  let!(:content) do
    channel.channel_contents.create!(user: user, title: "Issue", content: "old").tap { |c| c.channel_content_events.create!(event: event) }
  end

  describe "content generation" do
    before do
      allow_any_instance_of(Ai::ContentBuilderService).to receive(:humanize_enabled?).and_return(false)
    end

    it "streams phase, chunks and complete, and saves the post-processed text with a version" do
      allow_any_instance_of(Ai::ContentBuilderService).to receive(:generate_stream) do |_, &block|
        block.call("```markdown\nHello ")
        block.call("world\n```")
        { content: "```markdown\nHello world\n```" }
      end

      api_post "/api/v1/channels/#{channel.id}/contents/#{content.id}/generate", token

      expect(response.media_type).to eq("text/event-stream")
      expect(sse_events).to eq([
        [ "phase", { "phase" => "generating" } ],
        [ "chunk", "```markdown\nHello " ],
        [ "chunk", "world\n```" ],
        [ "complete", { "success" => true } ]
      ])
      expect(content.reload.content).to eq("Hello world")
      expect(content.version_history.last["content"]).to eq("old")
    end

    it "humanizes when the channel asks for it" do
      allow_any_instance_of(Ai::ContentBuilderService).to receive(:humanize_enabled?).and_return(true)
      allow_any_instance_of(Ai::ContentBuilderService).to receive(:generate_stream).and_return(content: "draft")
      allow_any_instance_of(Ai::ContentBuilderService).to receive(:humanize_stream) { |_, _text, &block| block.call("human") }

      api_post "/api/v1/channels/#{channel.id}/contents/#{content.id}/generate", token

      expect(sse_events.map(&:first)).to eq(%w[phase phase chunk complete])
      expect(sse_events[1]).to eq([ "phase", { "phase" => "humanizing" } ])
      expect(content.reload.content).to eq("human")
    end

    it "streams an error event for an AI failure" do
      allow_any_instance_of(Ai::ContentBuilderService).to receive(:generate_stream).and_raise(Ai::Client::ApiError, "model down")

      api_post "/api/v1/channels/#{channel.id}/contents/#{content.id}/generate", token

      expect(sse_events.last).to eq([ "error", { "message" => "model down" } ])
      expect(content.reload.content).to eq("old")
    end

    it "refines with the user's instructions and rejects blank ones, translated" do
      allow_any_instance_of(Ai::ContentBuilderService).to receive(:refine_stream) do |_, existing_content:, user_prompt:, &block|
        block.call("#{existing_content} #{user_prompt}")
        { content: "#{existing_content} #{user_prompt}" }
      end

      api_post "/api/v1/channels/#{channel.id}/contents/#{content.id}/refine", token, params: { user_prompt: "shorter" }
      expect(sse_events.first).to eq([ "phase", { "phase" => "refining" } ])
      expect(content.reload.content).to eq("old shorter")

      api_post "/api/v1/channels/#{channel.id}/contents/#{content.id}/refine", token, params: { user_prompt: "" }, locale: "sk"
      expect(sse_events).to eq([ [ "error", { "message" => I18n.t("channel_contents.errors.instructions_required", locale: :sk) } ] ])
    end
  end

  it "streams a RAG chat answer with the caller's citations" do
    allow_any_instance_of(Rag::ChatService).to receive(:chat_stream) do |_, question, conversation_history:, &block|
      block.call("Answer to #{question} (#{conversation_history.size})")
      { success: true, cited_event_ids: [ event.id ] }
    end

    api_post "/api/v1/chat/stream", token, params: { question: "what?", history: [ { role: "user", content: "hi" } ] }

    expect(sse_events.first).to eq([ "chunk", "Answer to what? (1)" ])
    complete = sse_events.last
    expect(complete.first).to eq("complete")
    expect(complete.last["cited_events"].first).to include("id" => event.id, "content" => "Bitcoin news")
  end

  it "streams the AI channel chat and creates the accepted proposals" do
    allow_any_instance_of(Ai::ChannelProposalService).to receive(:chat_stream) do |_, _message, conversation_history:, &block|
      block.call(type: "chunk", data: "Here is one")
      block.call(type: "proposal", data: { channels: [ { name: "Privacy" } ] })
      block.call(type: "complete", data: { success: true })
    end

    api_post "/api/v1/channels/ai/stream", token, params: { message: "newsletter", history: [] }
    expect(sse_events.map(&:first)).to eq(%w[chunk proposal complete])
    expect(sse_events[1].last).to eq("channels" => [ { "name" => "Privacy" } ])

    expect {
      api_post "/api/v1/channels/ai/bulk_create", token, params: {
        channels: [ { name: "Privacy", description: "d", language: "en", prompt: "p", settings: { relevance_threshold: 60, humanize_output: false } } ],
        templates: [ { name: "Digest", template: "# Digest" } ]
      }
    }.to change(Channel, :count).by(1)
    expect(json).to include("count" => 1, "notice" => I18n.t("channel_ai_chat.bulk_create.notice", count: 1))
    created = user.channels.find_by!(name: "Privacy")
    expect(created.relevance_threshold).to eq(60)
    expect(created.humanize_output?).to be(false)
    expect(user.reload.content_templates_list.map { |t| t["name"] }).to include("Digest")

    api_post "/api/v1/channels/ai/bulk_create", token, params: { channels: [] }
    expect(response).to have_http_status(:unprocessable_content)
  end
end
