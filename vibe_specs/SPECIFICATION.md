# Context

We are creating a web app for marketing content creation for different marketing channels. Primary use case
is my personal marketing with many channels. To understand, I will give you a common workflow.

I create a lot of content - blogs, social media posts (we will primarily fetch from Nostr, since it is the
easiest to work with programatically - I publish the same content on different social media, so Nostr can
be authoritative). I have multiple Nostr keys, and I also want to share some content from friends - they are
also Nostr public keys (npubs), but I specify "distance", which is how close we are together. Distance 0 is
my products, projects and services, distance 1 is my content, distance 2 is what I am interested in, but I have not created (I am posting about these on Nostr), distance 5 is close friends - their projects, services or content, distance 10 is what interests them but they have not created.

One daemon should be collecting these Nostr sources. Nostr sources can include links, parse them with trafilatura library.

Make the structure so the data feed can contain other sources as well, but we will not be implementing those,
but think RSS feeds for example.

Each post should include the distance, original source (nevent and npub), date published, etc.

OK, now we filled the database with some content (programatically through a daemon). Now we specify crew to
create posts for marketing channels. We will be using crewai for this, see below.

We need a web interface to create channels. Create types of channels with prefilled crew, but the crew and its tasks should be editable per channel.

Each channel should also have a language (English, Slovak, ...).

Example channels:
 - people who have bought my course "Digitálna bezpečnosť a súkromie". This course has description - what
  it is about, what interests people who have bought the course, etc. I send e-mail to these people only when
  I update the course in order not to spam them, but I would like to include news about my projects and content that might interest them based on the topic of the course and content. If I have a new offering, blog, etc. about this topic and it has not been shared in the newsletter, it should be included. If there is something important about digital security and privacy from my friends or my interest, it should be in the newsletter too. Ranking should be evaluated by a crew member, who's job is to curate this newsletter. Finding what has not been mentioned in previous edition and is interesting. Rank it based on distance (prefer my content and project, related content that is interesting but with higher distance can also get in, irrelevant content with high distance should not make it). The curator should limit the total size of the newsletter. Then the copywriter should take the curated content and write it, in a language configured for this channel. Each channel needs a description of what should be in. This course has update perhaps once per year, so there will be a lot more content than space in the newsletter. There should be a few headings with content (configurable, maybe up to 5 by default per newsletter) and then maybe "Quick notes" with just links with short description of a few more (maybe 10) things that might be interesting.
 - podcast newsletter subscribers - I send an e-mail newsletter to subscribers of my Slovak podcast Reči o živote, vesmíre a vôbec when new episode comes out. I always include all the blogs that I have written since the last newsletter. I also have another podcast - include one heading if there has been new episodes (you will learn about it from Nostr too), write about all these episodes too. Be mindful about language of content, I often write blogs in Slovak and English, include the Slovak version, but you can mention English-only content (describe it in Slovak).
 - I also have an english podcast Option Plus podcast. For this, never mention Slovak content (podcasts, blogs, ...), as most English speakers don't speak Slovak
 - There are Signal, Element and SimpleX groups on various topics. Examples:
     - R+Crypto - An alumni group of RWRI that is interested in crypto tech and trading. Members are traders, coders, experts, ...
     - R+AI - Same alumni, but only contains discussions about AI
    - OptionPlus Chat Cafe - generic chat group about liberty, cryptocurrencies, etc. Usually my followers. Slovak and Czech language is spoken in this channel
    - Paraguajski fesaci - A group of people with Paraguayan residency, interested in flag theory, crypto exchanges, offshore business and banking ... Slovak and Czech spoken
    - Global Opportunists - A group of people with Paraguayan residency, interested in flag theory, crypto exchanges, offshore business and banking ... English spoken
    - Monero and Freedom - a group about Monero, liberty, anarchism, freedom. I should not blindly promote stuff here, it should be very related to the topic of the group. Slovak and Czech spoken
  For these groups, you should proactively inform me to post things, formulate the text. Note that this is short-form text chat group, so short description and include links. Be mindful about language and topic of the group.

As you can see, the use-cases are diverse. For some posts, I should be reminded to post (like Signal chat groups), while for others, I initiate creation (newsletter).

Outputs should be in copyable markdown, but display it in HTML.

# Technology

We will use crewai, I include an example of how to use it in CREWAI.md.

Disable telemetry:
# Disable CrewAI telemetry only
os.environ['CREWAI_DISABLE_TELEMETRY'] = 'true'

# Disable all OpenTelemetry (including CrewAI)
os.environ['OTEL_SDK_DISABLED'] = 'true'

As for LLMs / models, we will allow the user to choose the inference API, make that configurable
in the config file. For sure support ollama and Venice API (OpenAI compatible API with apiBase:

        self.default_context_size = 128000
        self.default_model_name = "gpt-3.5-turbo"
        self.default_api_base = "https://api.venice.ai/api/v1"
    API key is in environment variable VENICE_API_KEY        
)

Allow definition of different models, for example if the last step is translation from English to
Slovak, it should be possible to use a different model and API for the translation than what was
used to generate the answer. So the translator agent in the crew should be able to use a custom model,
but use default if not specified.
    
For database, we use configurable data source - mysql or postgresql. Use SQL alchemy library
for database abstraction. 

For Nostr, we use nostr-sdk python library, see NOSTR.md

We use Python 3.11 and poetry for dependency management.

Researcher can use website scraping in crewai:

from crewai_tools import ScrapeWebsiteTool

# To enable scrapping any website it finds during it's execution
tool = ScrapeWebsiteTool()

# Initialize the tool with the website URL, 
# so the agent can only scrap the content of the specified website
tool = ScrapeWebsiteTool(website_url='https://www.example.com')

# Extract the text from the site
text = tool.run()
print(text)

For backend, we will use Flask.

Include basic user authentication.

For front-end, we will use Svelte
