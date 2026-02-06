 \# Tech Stack: Project Knot

\#\# 1\. Frontend (iOS Client)  
\* \*\*Language:\*\* Swift 6 (Strict concurrency for high-performance UI)  
\* \*\*Framework:\*\* SwiftUI  
\* \*\*Design System:\*\* \*\*shadcn/ui (SwiftUI Port)\*\*  
    \* \*Purpose:\* Uses native Swift implementations of shadcn components (Cards, Buttons, Inputs) to maintain the clean, minimalist aesthetic.  
\* \*\*Icons:\*\* Lucide-Swift (Consistent with shadcn visual language)  
\* \*\*Data Persistence:\*\* SwiftData (Local storage for the Partner Vault and offline access)

\#\# 2\. Backend (AI & Orchestration)  
\* \*\*Environment:\*\* Python 3.12+ / FastAPI  
\* \*\*Orchestration:\*\* \*\*LangGraph\*\*  
    \* \*Purpose:\* Manages the "Vibe Crawler" logic, allowing the AI to reason through multiple data sources before presenting the "Choice of 3."  
\* \*\*AI Model:\*\* Gemini 1.5 Pro (via Vertex AI)  
\* \*\*Validation:\*\* Pydantic AI (Ensures AI output strictly follows the defined interest/vibe schemas)

\#\# 3\. Data & Memory  
\* \*\*Database:\*\* Supabase (PostgreSQL)  
\* \*\*Vector Search:\*\* pgvector (For semantic "Hint" retrieval and partner preference mapping)  
\* \*\*Auth:\*\* Supabase Auth (Native Apple Sign-In integration)

\#\# 4\. Integration Layer (The Aggregator)  
\* \*\*Event Data:\*\* Ticketmaster API \+ PredictHQ (Broad-spectrum event aggregation)  
\* \*\*Dining/Vibe:\*\* Yelp Fusion API \+ OpenTable/Resy  
\* \*\*Commerce:\*\* Shopify Storefront API \+ Amazon Associates  
\* \*\*Crawling:\*\* Firecrawl (For parsing curated city guides and "Vibe" lists into LLM-ready data)

\#\# 5\. Deployment & Infrastructure  
\* \*\*Hosting:\*\* Vercel (For FastAPI backend)  
\* \*\*Task Scheduling:\*\* Upstash (To manage the 14/7/3 day proactive notification triggers)  
