# /Users/juraj/projects/lievik/scripts/add_cypherpunk_source.py
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from lievik.app import create_app, db
from lievik.models import User, Source

app = create_app()

with app.app_context():
    # Assuming you have a user to associate this source with.
    # Replace 'your_username' with an actual username from your User table.
    # If you don't have a user, you might need to create one first or adjust this.
    user = User.query.filter_by(username='jooray').first()

    if not user:
        print("User not found. Please create a user first or specify an existing one.")
    else:
        description = """Cypherpunk meetup is a side-event to BTCPrague, organized each year by volunteers and financed through crowdfunding. We have a cool manifesto for this year's 2025 meetup:

🔥 Webs, grids, meshes
🫂 Peer-to-peer Everything

We often get smitten by the picture of the world as a hierarchy: Someone always above, someone always below. Bosses, leaders, rulers, chains of command, all wrapped in societal imperatives.

But if you zoom out, the real world doesn’t run on pyramids – it runs on webs. Across the world, resilient communities and decentralized networks are quietly rewriting the rules. They don’t wait for permission. They don’t hold press conferences. They operate in whispers, in code, in trade, in trust. They don’t change the world top-down.They change it side-to-side, network to network.

Bitcoin has the power to turn a gathering into a market. A message into a contract. A connection into a livelihood. It empowers not just the individual, but the network—and in that network, we are seeing real resistance grow. And here, Bitcoin can play a critical role: as private money, as collateral, as a tool for exit.

Come to learn what works, meet those who’ve walked the path in different shoes and get inspired about how to connect the dots, the nodes and the webs into an unbeatable movement.

Because the people building the future aren’t climbing ladders. They’re weaving webs.

Come to ask not “How do we win?”—but “How do we weave?”"""

        new_source = Source(
            user_id=user.id,
            type='nostr',
            identifier='npub17uy9rem33d7fzqzql4hazvnpdhc90wdp0tucfzyrc7ku0u0wjyys9m3kyk',
            base_distance=0.5,  # Default or adjust as needed
            is_active=True,
            description=description  # Added description field
        )
        db.session.add(new_source)
        db.session.commit()
        print(f"Source 'npub17uy9rem33d7fzqzql4hazvnpdhc90wdp0tucfzyrc7ku0u0wjyys9m3kyk' added for user '{user.username}' with description.")
