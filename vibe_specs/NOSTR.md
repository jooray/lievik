# NOSTR

For nostr, we will use nostr-sdk package

The nostr-sdk package is available on the public PyPI:

pip install nostr-sdk 

Alternatively, you can manually add the dependency in your requrements.txt, setup.py, etc.:

nostr-sdk==0.42.1

Import the library in your code:

from nostr_sdk import *

## Example fetch

import asyncio
from datetime import timedelta

from nostr_sdk import Client, Filter, Events, Kind, KindStandard


async def fetch():
    client = Client()

    await client.add_relay("wss://relay.damus.io")
    await client.connect()

    filter: Filter = Filter().kind(Kind.from_std(KindStandard.METADATA)).limit(3)
    events: Events = await client.fetch_events(filter, timedelta(seconds=10))

    filter: Filter = Filter().kind(Kind.from_std(KindStandard.TEXT_NOTE)).limit(5)
    events: Events = await client.fetch_events_from(["wss://relay.damus.io"], filter, timedelta(seconds=10))


if __name__ == '__main__':
   asyncio.run(fetch())

## Filters

Though a web-socket subscription model relays can surface events that meet specific criteria on request. The means by which these requests maybe submitted are JSON filters objects which can be constructed using a range of attributes, including ids, authors, kinds and single letter tags, along with timestamps, since/until and record limit for the query.
Create Filters
Rust
Python

The following code examples all utilize the Filters() along with associated methods to create filter objects and print these in JSON format using the as_json() method.

Filtering events based on a specific event ID using id().

# Filter for specific ID
print("  Filter for specific Event ID:")
f = Filter().id(event.id())
print(f"     {f.as_json()}")

Filtering events by author using author().

# Filter for specific Author
print("  Filter for specific Author:")
f = Filter().author(keys.public_key())
print(f"     {f.as_json()}")

Filtering events based on multiple criteria. In this case, by public key using pubkey() and kind using kind().

# Filter by PK and Kinds
print("  Filter with PK and Kinds:")
f = Filter()\
    .pubkey(keys.public_key())\
    .kind(Kind(1))
print(f"     {f.as_json()}")

Filtering for specific text strings using search().

# Filter for specific string
print("  Filter for specific search string:")
f = Filter().search("Ask Nostr Anything")
print(f"     {f.as_json()}")

Restricting query results to specific timeframes (using since() and until()), as well as limiting search results to a maximum of 10 records using limit().

print("  Filter for events from specific public key within given timeframe:")
# Create timestamps
date = datetime.datetime(2009, 1, 3, 0, 0)
timestamp = int(time.mktime(date.timetuple()))
since_ts = Timestamp.from_secs(timestamp)
until_ts = Timestamp.now()

# Filter with timeframe
f = Filter()\
    .pubkey(keys.public_key())\
    .since(since_ts)\
    .until(until_ts)
print(f"     {f.as_json()}")

# Filter for specific PK with limit
print("  Filter for specific Author, limited to 10 Events:")
f = Filter()\
    .author(keys.public_key())\
    .limit(10)
print(f"     {f.as_json()}")

Finally, filtering using hashtags (hashtag()), NIP-12 reference tags (reference()) and identifiers (identifiers()), respectively.

# Filter for Hashtags
print("  Filter for a list of Hashtags:")
f = Filter().hashtags(["#Bitcoin", "#AskNostr", "#Meme"])
print(f"     {f.as_json()}")

# Filter for Reference
print("  Filter for a Reference:")
f = Filter().reference("This is my NIP-12 Reference")
print(f"     {f.as_json()}")

# Filter for Identifier
print("  Filter for a Identifier:")
identifier = event2.tags().identifier()
if identifier is not None:
    f = Filter().identifier(identifier)
    print(f"     {f.as_json()}")

JavaScript
Kotlin
Swift
Flutter
Modify Filters
Rust
Python

Adding more conditions to existing objects can be done by simply calling the relevant method on the instance of the object. In this example we create a initial filter with pubkeys(), ids(), kinds() and a single author() then modify the object further to include another kind (4) to the existing list of kinds (0, 1).

Similarly, the range of 'remove' methods (e.g. remove_kinds()) allow us to take an existing filter and remove unwanted conditions without needed to reconstruct the filter object from scratch.

# Modifying Filters (adding/removing)
f = Filter()\
    .pubkeys([keys.public_key(), keys2.public_key()])\
    .ids([event.id(), event2.id()])\
    .kinds([Kind(0), Kind(1)])\
    .author(keys.public_key())

# Add an additional Kind to existing filter
f = f.kinds([Kind(4)])

# Print Results
print("  Before:")
print(f"     {f.as_json()}")
print()

# Remove PKs, Kinds and IDs from filter
f = f.remove_pubkeys([keys2.public_key()])
print(" After (remove pubkeys):")
print(f"     {f.as_json()}")

f = f.remove_kinds([Kind(0), Kind(4)])
print("  After (remove kinds):")
print(f"     {f.as_json()}")

f = f.remove_ids([event2.id()])
print("  After (remove IDs):")
print(f"     {f.as_json()}")

JavaScript
Kotlin
Swift
Flutter
Other Filter Operations
Rust
Python

We can parse existing filter JSON object using the from_json() method when instantiating a filter object.

# Parse filter
print("  Parse Filter from Json:")
f_json = f.as_json()
f = Filter().from_json(f_json)
print(f"     {f.as_record()}")

Furthermore, it is possible to create filter records more formally using the FilterRecord class.

print("  Construct Filter Record and extract author:")
# Filter Record
fr = FilterRecord(ids=[event.id()],authors=[keys.public_key()], kinds=[Kind(0)], search="", since=None, until=None, limit=1, generic_tags=[])
f = Filter().from_record(fr)
print(f"     {f.as_json()}")

To perform a logical test and determine if a given event object matches existing filter conditions the match_event() method can be used.

print("  Logical tests:")
f = Filter().author(keys.public_key()).kind(Kind(1))
print(f"     Event match for filter: {f.match_event(event)}")
print(f"     Event2 match for filter: {f.match_event(event2)}")


## Linking

When you are linking to Nostr events, use https://njump.me/nevent........
