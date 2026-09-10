> **Archived.** This was the original University of Zambia Final Year Project proposal. The FYP itself
> ended up going a different direction, and this project continued separately as a personal portfolio
> build — see [`../ZamHealthWatch_Project_Brief.md`](../ZamHealthWatch_Project_Brief.md) for the current
> spec. Kept here for history only; nothing in this file is the live plan.

# ZamHealth Watch — FYP Proposal

University of Zambia | 2024/25

**UNIVERSITY OF ZAMBIA**
School of Natural Sciences
Department of Computer Science

**FINAL YEAR PROJECT PROPOSAL**

**ZamHealth Watch:** *A Real-Time Disease Outbreak Tracking and Early Warning System for Zambia*

| | |
|---|---|
| **Programme** | Bachelor of Science in Software Engineering |
| **Academic Year** | 2024 / 2025 |

## 1. Introduction

The burden of infectious disease in Zambia remains one of the most pressing public health challenges of our time. Diseases such as cholera, malaria, typhoid, and emerging viral infections continue to claim thousands of lives annually, with outbreaks often escalating beyond control before health authorities are able to mount an effective response. A core driver of this problem is the absence of a centralised, real-time digital system capable of aggregating disease case data, identifying geographic hotspots, and issuing timely early warnings to both healthcare workers and the general public.

ZamHealth Watch is proposed as a web-based disease outbreak tracking and early warning platform designed specifically for the Zambian context. By combining an interactive geospatial disease map, an artificial intelligence (AI) outbreak prediction model, a health authority management dashboard, and an SMS/USSD reporting channel accessible to rural communities without smartphones, the system aims to bridge the critical gap between disease occurrence and institutional response.

## 2. Background and Motivation

Zambia has experienced repeated and devastating disease outbreaks over the past two decades. The 2017–2018 cholera outbreak in Lusaka infected over 5,000 people and caused at least 83 deaths before it was brought under control. Malaria remains endemic across most of the country, with the 2023 Zambia Malaria Indicator Survey reporting a national parasite prevalence rate of 28%.

Currently, disease case data in Zambia is largely collected on paper forms at the facility level, which are then compiled and submitted to District Health Offices (DHOs) and eventually the Ministry of Health (MOH). This process is slow, prone to transcription errors, and offers no real-time visibility into emerging outbreaks.

Globally, disease surveillance systems such as the US CDC's National Notifiable Diseases Surveillance System (NNDSS) and the WHO's Early Warning, Alert and Response System (EWARS) have demonstrated the value of digitised, real-time case reporting. No comparable national system exists in Zambia.

## 3. Problem Statement

Zambia lacks a centralised, real-time digital system for disease outbreak tracking and early warning. Existing surveillance mechanisms rely on manual, paper-based data collection, resulting in delayed detection of outbreaks, poor geographic visibility of disease spread, and inadequate communication of risk to frontline health workers and communities.

## 4. Objectives

**Main Objective:** To design, develop, and evaluate a real-time web-based disease outbreak tracking and early warning system for Zambia, integrating AI-driven risk prediction, geospatial visualisation, and SMS/USSD-based reporting.

**Specific Objectives:**

- Develop a web portal through which health facilities can log confirmed and suspected disease cases in real time.
- Implement an interactive geospatial disease heatmap displaying case distributions across Zambia's provinces and districts.
- Build and integrate a machine learning model capable of predicting disease outbreak risk by district.
- Integrate an SMS/USSD channel using Africa's Talking API for rural health workers and citizens.
- Develop a Ministry of Health dashboard providing aggregated analytics and alert management tools.
- Implement an automated early warning alert system.
- Evaluate the system through functional testing, user acceptance testing, and performance benchmarking.

## 5. Scope and Limitations

Covered all ten provinces of Zambia; tracked cholera, malaria, typhoid, COVID-19, and measles. AI model trained on WHO AFRO and Zambia MOH historical data. Designed as a prototype — full national deployment would require MOH partnership and security auditing beyond FYP scope.

## 6. Original Proposed Architecture

Three-tier: React.js frontend, Node.js/Express REST API, PostgreSQL database (Supabase), Python/Flask AI microservice (scikit-learn, Facebook Prophet), Africa's Talking SMS/USSD gateway, Leaflet.js mapping layer.

## 7. Original Technology Stack

- **Frontend:** React.js, Tailwind CSS, Leaflet.js, Recharts
- **Backend:** Node.js, Express.js, PostgreSQL, JWT, Supabase
- **AI/ML:** Python, Flask, scikit-learn, Facebook Prophet, Pandas, NumPy
- **Communications:** Africa's Talking SMS & USSD API
- **DevOps:** GitHub, Render/Railway, Postman

## 8. Original Methodology

Agile, two-week sprints. Requirements gathering via literature review; UML-documented system design (use case, class, sequence, ER diagrams); development across three parallel streams (frontend, backend API, AI microservice); unit/integration/UAT/performance testing.

## References

- World Health Organization (2023). *Zambia: Disease Outbreak News.* Geneva: WHO.
- Zambia Ministry of Health (2022). *Annual Health Statistical Bulletin.* Lusaka: MOH.
- Africa Centres for Disease Control and Prevention (2023). *Africa CDC Integrated Disease Surveillance and Response.* Addis Ababa: Africa CDC.
- Brownstein, J. S., Freifeld, C. C., & Madoff, L. C. (2009). Digital disease detection — harnessing the Web for public health surveillance. *New England Journal of Medicine*, 360(21), 2153–2157.
- Taylor, L. H., Latham, S. M., & Woolhouse, M. E. (2001). Risk factors for human disease emergence. *Philosophical Transactions of the Royal Society B*, 356(1411), 983–989.
- Africa's Talking (2024). *SMS and USSD API Documentation.* Nairobi: Africa's Talking Ltd.
- Facebook / Meta (2024). *Prophet: Forecasting at Scale.*
