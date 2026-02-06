\# Product Requirements Document: Project Knot

\*\*\[Product Title & Tagline\]:\*\* Knot | \*Relational Excellence on Autopilot.\*  
\*\*\[Document Owner\]:\*\* \[Your Name\]    
\*\*\[Last Updated Date\]:\*\* February 3, 2026    
\*\*\[Status\]:\*\* Draft  

\---

\#\# PRD Phase 1: Alignment Overview

\#\#\# Problem Statement   
Partners in long-term relationships face a \*\*"Thoughtfulness Gap."\*\* While they have a genuine desire to be a "better partner," they lack a systematic way to capture preferences and execute creative plans. This manifests in three specific ways:  
\* \*\*Cognitive Load of Intentionality:\*\* The mental tax of remembering subtle hints and planning "spiced up" dates leads to decision fatigue and "roommate syndrome."  
\* \*\*Occasion Paralysis:\*\* Users often scramble or default to generic gifts because they haven't tracked their partner’s evolving tastes over time.  
\* \*\*The Social Comparison Bar:\*\* Social media has heightened the "aesthetic" expectations of relationships. Users feel pressure to curate meaningful experiences that look and feel high-quality but lack the creative "second brain" to make it happen without significant stress.

\#\#\# Market and Strategic Context  
We are witnessing the emergence of the \*\*"Intentionality Economy."\*\* After the peak of dating app fatigue, the market is shifting toward \*\*"Relationship Infrastructure."\*\* \* \*\*External Landscape:\*\* There is a significant gap for a high-utility \*\*"Execution Engine"\*\* that bridges the gap between digital data (preferences/hints) and physical experiences (dates/gifts).  
\* \*\*Strategic Driver:\*\* Scale of personalization. Unlike traditional concierge services, an AI-driven agent allows for infinite, real-time mapping between a specific "Vibe" and live data streams.

\---

\#\# Customer & User Personas (Jobs to be Done)

| The Job (JTBD) | Desired Outcome (Success) | Current "Hacky" Solution |  
| :--- | :--- | :--- |  
| \*\*"I want to buy my partner a meaningful gift."\*\* | Find a gift that proves I listen and understand them, without the stress of a blind search. | Generic Amazon searches, scrolling old texts, or asking friends. |  
| \*\*"I want to do something fun/new with my partner."\*\* | Break the routine with an activity that fits our specific schedule, budget, and "vibe." | Scrolling Yelp/Instagram for hours; ending up at the same 3 spots. |  
| \*\*"I want to be a 'proactive' partner."\*\* | Feel "on top of it" and avoid the guilt of realizing an occasion is tomorrow. | Setting generic iPhone reminders that get ignored or snoozed. |

\---

\#\# Value of Solving the Problem  
\* \*\*For the User:\*\* Emotional security, reduced cognitive load, and the "Social Status" of being a consistently thoughtful partner. The user gets 100% of the credit for the outcome while the app handles the "administrative" work.  
\* \*\*For the Business:\*\* High "stickiness" and lifetime value (LTV). Relationship maintenance is an evergreen need. The platform is built for high-intent affiliate revenue through gift procurement and reservation bookings.  
\* \*\*Personalization ROI:\*\* Highly personalized suggestions lead to better gifts and dates that are significantly more likely to be successful, reinforcing the "Second Brain" value.

\---

\#\# KPIs & Success Criteria  
\* \*\*Recommendation "Hit" Rate:\*\* % of users who provide positive feedback (4-5 stars) or engage in a "Save/Share" action after receiving a trio of suggestions.  
\* \*\*Engagement & Discovery Depth:\*\* Average number of personalized recommendations viewed per session during a "Planning Window" (14 days prior to a milestone).  
\* \*\*Growth & Social Proof:\*\* Conversion rate of "Success Feedback" (internal app rating) to public App Store reviews at the moment of peak gratitude.

\---

\#\# Known Constraints  
\* \*\*Strict Interest Filtering:\*\* Suggestions are strictly limited to the 5 interests provided during onboarding. The AI is prohibited from "improvised" recommendations outside these bounds.  
\* \*\*Multi-Source API Integrity:\*\* The experience relies on the availability and uptime of 3rd party commerce and booking APIs.   
\* \*\*System DND:\*\* The app must respect system-level "Do Not Disturb" settings, queuing notifications until the user is in an active window.

\---

\#\# Feature Definition (MVP)

\#\#\# 1\. The Partner Vault (Onboarding)  
A foundational data profile capturing:  
\* \*\*Core Details:\*\* Name, tenure, cohabitation status, and location.  
\* \*\*Interests & Dislikes:\*\* Exactly 5 specific Likes and 5 specific "Hard Avoids."  
\* \*\*Milestones:\*\* Birthday, Anniversary, and key holiday preferences.  
\* \*\*Aesthetic/Vibe Check:\*\* Multi-select visual anchors (e.g., \*Quiet Luxury, Street/Urban, Outdoorsy, Vintage\*).  
\* \*\*Financial Guardrails:\*\* Defined budget tiers for "Just Because" dates vs. "Major Milestone" gifts.  
\* \*\*Love Language Profile:\*\* Primary and secondary ways the partner receives affection.

\#\#\# 2\. Proactive "iMessage-style" Alerts  
An automated assistant that initiates planning through rich notifications triggered 14, 7, and 3 days before saved milestones.  
\* \*\*The Logic:\*\* Cross-references Vault data with real-time event/product APIs.  
\* \*\*Real-time Validation:\*\* Only suggests events or items with confirmed availability at the time of the push.

\#\#\# 3\. The Hint Capture (Second Brain)  
A low-friction, persistent input (Text or Voice-to-Text) on the home screen for the user to record fleeting observations (e.g., \*"She mentioned she liked that specific perfume"\*). These are used to weight future milestone suggestions.

\#\#\# 4\. Choice-of-Three Recommendations  
Whenever a trigger occurs, the user is presented with exactly \*\*three curated cards\*\*.  
\* \*\*Interactive Learning:\*\* Every selection or "Refresh" (re-roll) action influences the weight of future suggestions.  
\* \*\*Manual Override:\*\* Allows the user to flex their "Vibe" or interest for a specific evening without changing the permanent profile.

\---

\#\# Recommended Solution (Functionality & Logic)

\#\#\# The Multi-Source Aggregator  
The engine is built on a tiered data ingestion strategy:  
\* \*\*API-Driven Commerce:\*\* Integrations with global ticketing, reservation, and e-commerce platforms to pull real-time inventory.  
\* \*\*Local "Vibe" Feeds:\*\* Ingests data from curated city guides and lifestyle platforms to identify trending "pop-up" experiences or restaurant openings.  
\* \*\*Semantic Filtering:\*\* Raw data is passed through an LLM that maps "events" to the Partner Vault. If a restaurant is trending, the system checks its metadata against the partner’s \*\*Aesthetic Vibe\*\* and \*\*Budget Tiers\*\*.

\#\#\# Availability-Aware Execution  
\* \*\*Synced Mode:\*\* If a calendar (Google/iCal) is connected, the AI proposes suggestions during identified "white space."  
\* \*\*Predictive Mode (Fallback):\*\* If no calendar is synced, the system defaults to a \*\*"Weekend Outlook"\*\* push every Thursday morning.

\---

\#\# E2E User Experience (UX) & Design

\#\#\# The "Hero Journey" Narrative  
1\. \*\*The Anticipatory Trigger:\*\* 10 days before a birthday, the user receives a rich notification: \*"Alex’s birthday is in 10 days. I’ve found 3 'Quiet Luxury' options based on her recent interest in 'Gardening'."\*  
2\. \*\*The Selection (Choice of 3):\*\* User enters the app to find a horizontal scroll of three distinct cards.  
3\. \*\*The Feedback Loop:\*\* If the user isn't feeling the options, they hit \*\*"Refresh."\*\* The system immediately generates a new trio, excluding the attributes of the rejected cards (e.g., "Too Low-key").  
4\. \*\*The Frictionless Hand-off:\*\* User selects the winner. The app deep-links directly to the merchant’s product page. The user completes the transaction through the merchant’s checkout, remaining the "Hero" of the gift.

\---

\#\# Known Product Requirements Definition

\#\#\# Functional Requirements  
\* \*\*F1 (Strict Interest Filter):\*\* Recommendations must be 100% grounded in the 5 interests \+ captured hints.  
\* \*\*F2 (Choice Logic):\*\* Every trigger must generate exactly three distinct cards.  
\* \*\*F3 (Deep-linking):\*\* The app must support universal deep-links to external commerce/booking platforms.  
\* \*\*F4 (DND Integration):\*\* System "Do Not Disturb" must always trump app notifications.

\#\#\# Non-Functional Requirements  
\* \*\*Standard Performance:\*\* AI recommendation generation for the "Choice of 3" must be \*\*\< 3 seconds\*\*.  
\* \*\*Integrity:\*\* The app must verify the destination URL is active before presenting the card.  
\* \*\*Privacy:\*\* Partner Vault and "Hint Capture" data must be encrypted at rest.

\---

\#\# Scope / Out-of-Scope  
\* \*\*In-Scope:\*\* Onboarding (Vault), 3-Card Selection, Proactive iMessage-style Notifications, Hint Capture (Text/Voice), and Deep-Linking.  
\* \*\*Out-of-Scope:\*\* In-app payments (direct hand-off only), AI Chat interface, Partner-facing features, and "Group" gift coordination.  
