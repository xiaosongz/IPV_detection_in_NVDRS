# UM-GPT API Access Research and Request

**Date:** October 17, 2025
**Purpose:** Research UM-GPT service and draft API access request for IPV detection project
**Status:** Draft request ready for submission

---

## Executive Summary

Researched University of Michigan's UM-GPT service (custom AI toolkit with API gateway) and drafted a professional API access request for our IPV detection research project. The service provides access to GPT-4o, Claude 3.5 Haiku, and other models in a private U-M cloud environment that meets FERPA and moderate sensitivity data standards. Our deidentified NVDRS narratives align well with the service's privacy requirements.

---

## Table of Contents

1. [UM-GPT Service Overview](#um-gpt-service-overview)
2. [Available Models](#available-models)
3. [API Access Process](#api-access-process)
4. [Data Privacy and Security](#data-privacy-and-security)
5. [Pricing and Usage](#pricing-and-usage)
6. [Our Project Alignment](#our-project-alignment)
7. [Draft API Request](#draft-api-request)
8. [Next Steps](#next-steps)

---

## UM-GPT Service Overview

### What It Is

The University of Michigan is the first university in the world to provide a custom suite of generative AI tools to its community. The service consists of three tiers:

1. **U-M GPT** - Free web interface for general use by all U-M community members
2. **U-M Maizey** - AI assistant integrated with Canvas and other university systems
3. **U-M GPT Toolkit** - Advanced API gateway for developers and researchers (this is what we need)

### Infrastructure

- Housed in a **private cloud environment on Microsoft Azure**
- Uses Azure OpenAI services and U-M hosted open-source models
- Meets privacy and security standards for institutional data of **Moderate sensitivity**, including FERPA data
- Data shared with ITS AI Services will **NOT be used to train AI models**
- Private, secure, and meets U-M privacy standards

### Key Privacy/Security Features

✅ Data NOT used for model training
✅ Private U-M cloud environment (not external third-party)
✅ Complies with SPG 601.07 (Responsible Use), 601.11 (Privacy), 601.12 (Data Stewardship)
✅ Supports moderate sensitivity data including FERPA-protected records
✅ Self-cleaning 15-minute cache for efficient usage

---

## Available Models

### Text Models Available via U-M GPT Toolkit

**Foundational Models:**
- **GPT-4o** - Latest OpenAI model, best for general tasks
- **GPT-4 Turbo** - Previous generation, high capability
- **GPT-3.5 Turbo** - Cost-effective option
- **Claude 3.5 Haiku** - Anthropic's efficient model
- **Llama 3.2 and Llama 3** - Open-source models hosted by U-M

**Reasoning Models:**
- **o3-mini** - Advanced reasoning for complex multi-step logic

**Image Generation:**
- **GPT-Image-1 (DALL-E 3)** - Standard definition 1024x1024 images

### Model Capabilities

**Foundational models** - Best for:
- Summarization
- Translation
- Basic Q&A
- Mood/tone analysis
- Basic coding

**Reasoning models** - Best for:
- Complex multi-step logic
- Advanced math
- Intricate planning
- Puzzle-solving
- Advanced coding

---

## API Access Process

### Eligibility

- All active U-M faculty, staff, and students (Ann Arbor, Flint, Dearborn, Michigan Medicine)
- Intended primarily for researchers, developers, and graduate students with technical expertise

### Critical Requirement

**Must have a valid Shortcode** (6-digit code in U-M financial system for departmental/project billing)
- Students typically need faculty/department sponsorship to obtain a Shortcode

### Request Process

1. **Submit Access Request**
   - Use ITS Service Request Form: https://teamdynamix.umich.edu/TDClient/30/Portal/Requests/TicketRequests/NewForm?ID=DvuZKcSwP6w_&RequestorType=Service
   - AI Services team will contact you after submission

2. **What to Include in Request**
   - Project description and research objectives
   - Shortcode for billing
   - Expected usage patterns/volume
   - Technical requirements (specific models needed)
   - Principal Investigator information (for research projects)
   - Data sensitivity level

3. **After Approval**
   - Create your own toolkit API keys
   - Access to billing dashboard (Tableau) for usage monitoring
   - Access to GitHub repository with documentation and example code
   - API gateway access to Azure OpenAI and other models

---

## Data Privacy and Security

### Permitted Data Types

✅ Institutional data of Moderate sensitivity
✅ FERPA-protected educational records
✅ General research data

❌ Highly sensitive data (unless specifically approved)

### Requirements

- Must follow SPG 601.07, 601.11, and 601.12 policies
- Check the Sensitive Data Guide to IT Services for permitted data types
- Data security considerations should be addressed early in research planning

### Data Handling Guarantees

- Data will **NOT be used for model training**
- Housed in **private U-M cloud environment**
- **Not sent to external third-party services**
- Complies with university data protection standards

---

## Pricing and Usage

### Cost Structure

- **U-M GPT (web interface):** FREE
- **U-M GPT Toolkit (API):** Monthly billing based on usage
- Specific per-token rates: Not publicly disclosed (provided after approval)
- Pricing subject to change

### Billing and Monitoring

- Monthly invoices charged to your Shortcode
- **Tableau dashboard** for real-time usage monitoring
- Default access for requestor and/or Principal Investigator
- Additional dashboard users can be added by request

### Usage Limits (Web Interface - for reference)

- Text models: ~75 prompts per hour
- Image models: ~10 prompts per hour
- API limits likely custom negotiated based on project needs

---

## Our Project Alignment

### Why UM-GPT is Ideal for IPV Detection Project

#### 1. **Data Privacy Match**

Our NVDRS narratives are **fully deidentified**:
- ❌ No names (only relationships: "the decedent", "his girlfriend", "her boyfriend")
- ❌ No absolute dates (only relative times: "3 years ago", "recently", "past month")
- ❌ No specific locations or identifiable information
- ✅ Meets **moderate sensitivity data standards**

**Example Deidentified Narrative:**
```
"The decedent was found deceased in her home from an apparent drug overdose.
Her sister reported that the decedent had been in a relationship with a man
who was physically and emotionally abusive. The boyfriend would control all
aspects of the decedent's life, including her finances and social interactions.
The decedent had previously been hospitalized for injuries sustained during
an argument with the boyfriend."
```

#### 2. **Model Access**

Need access to multiple models for comparison:
- ✅ GPT-4o (primary model)
- ✅ Claude 3.5 Haiku (comparison)
- ✅ o3-mini (for reasoning-enhanced detection)

#### 3. **Research Scale**

- **Testing phase:** 404 narratives (moderate usage)
- **Production phase:** ~60,000 narratives (high usage, cost estimates needed)
- Full token usage tracking and cost monitoring built into our system

#### 4. **Technical Infrastructure**

We already have:
- ✅ Config-driven experiment harness
- ✅ SQLite/PostgreSQL storage with full tracking
- ✅ Token usage and cost monitoring
- ✅ 207 unit tests + integration tests
- ✅ Automated metrics reporting (F1, precision, recall)
- ✅ Reproducible research framework

#### 5. **Research Value**

- Public health research on suicide prevention
- Detecting IPV as contributing factor in suicide deaths
- Peer-reviewed publication planned
- Repository as supplementary materials

---

## Draft API Request

### Ready for Submission

**Subject: API Access Request for IPV Detection Research in Suicide Narratives**

I am requesting access to the U-M GPT Toolkit API gateway to support an ongoing public health research project developing LLM-based classification methods to detect intimate partner violence (IPV) as a contributing factor in suicide cases using deidentified NVDRS (National Violent Death Reporting System) narratives. This research aims to improve surveillance and intervention strategies for suicide prevention, with findings intended for peer-reviewed publication. The project has completed development of a config-driven experiment harness with full SQLite/PostgreSQL tracking, 207 unit tests, and automated metrics reporting (F1, precision, recall).

**Technical requirements:** Access to GPT-4o, Claude 3.5 Haiku, and potentially o3-mini for model comparison. The testing phase involves 404 narratives (moderate usage), with a planned production run of approximately 60,000 narratives pending optimal configuration identification. Our architecture includes token usage tracking and cost monitoring. **Data privacy:** All NVDRS narratives are fully deidentified—containing no names (only relationships like "the decedent", "his girlfriend"), no absolute dates (only relative times), no specific locations, and no identifiable information. This meets moderate sensitivity data standards and aligns with UM-GPT's FERPA compliance capabilities. Data will remain within the U-M private cloud environment and will not be used for model training.

I would appreciate a consultation to discuss Shortcode setup for monthly billing, usage monitoring via the Tableau dashboard, and implementation best practices. Could we schedule a meeting to finalize access and ensure proper configuration for reproducible research workflows? I am available at your earliest convenience and can provide additional technical details about the project architecture or repository structure as needed.

---

### Additional Context for Form Fields

**Department/Unit:** [Your department]
**Faculty Sponsor:** [If applicable]
**Project Duration:** [Expected timeline]
**Estimated Monthly Usage:** Testing phase (moderate), Production phase (high—will need cost estimates for 60K narratives)
**Data Classification:** Moderate sensitivity (deidentified research data)
**Shortcode for Billing:** [To be determined / Request assistance]

---

## Next Steps

### Before Submitting Request

1. **Obtain or Confirm Shortcode**
   - Contact department/faculty sponsor
   - Obtain 6-digit billing code
   - Or request assistance in form if unavailable

2. **Prepare Supporting Information**
   - IRB approval documentation (if applicable for NVDRS data)
   - Faculty PI information (if student/postdoc)
   - Estimated timeline for project

3. **Review UM-GPT Documentation**
   - Visit https://its.umich.edu/computing/ai
   - Review privacy notice and policies
   - Attend virtual office hours if questions

### Submission Process

1. **Submit Request Form**
   - URL: https://teamdynamix.umich.edu/TDClient/30/Portal/Requests/TicketRequests/NewForm?ID=DvuZKcSwP6w_&RequestorType=Service
   - Use draft request text above
   - Complete all required fields

2. **Join Mailing List**
   - ITS-AI-Services-Notify for updates and announcements

3. **Wait for Contact**
   - AI Services team will reach out after submission
   - Prepare to discuss technical details and implementation

4. **Schedule Consultation**
   - Request meeting to discuss:
     - Shortcode billing setup
     - Tableau dashboard access
     - API key creation and management
     - Best practices for research workflows
     - Cost estimates for production run

### After Approval

1. **Access GitHub Documentation**
   - Review example code and API documentation
   - Understand Azure OpenAI-compatible endpoints

2. **Create API Keys**
   - Set up authentication
   - Test with small sample

3. **Configure Project**
   - Update `.env` file with UM-GPT credentials
   - Modify API endpoints in experiment configs
   - Run integration tests

4. **Monitor Usage**
   - Access Tableau dashboard
   - Track token usage and costs
   - Adjust configurations as needed

5. **Begin Testing Phase**
   - Run 404 narrative test with multiple models
   - Compare results to current OpenAI/Anthropic API results
   - Evaluate performance and cost

6. **Scale to Production**
   - After testing validation
   - Review cost estimates
   - Run full 60,000 narrative production run

---

## Important Links

- **Request API Access:** https://teamdynamix.umich.edu/TDClient/30/Portal/Requests/TicketRequests/NewForm?ID=DvuZKcSwP6w_&RequestorType=Service
- **ITS AI Services:** https://its.umich.edu/computing/ai
- **Support:** https://its.umich.edu/computing/ai/support
- **Generative AI Portal:** https://genai.umich.edu/
- **Privacy Notice:** https://its.umich.edu/computing/ai/privacy-notice

---

## Key Advantages of UM-GPT for Our Project

### Alignment with Project Requirements

| Requirement | UM-GPT Capability | Status |
|-------------|-------------------|--------|
| Model access (GPT-4o, Claude) | ✅ Available via API | Perfect match |
| Data privacy (deidentified) | ✅ Supports moderate sensitivity | Meets standards |
| Cost monitoring | ✅ Tableau dashboard | Built-in |
| No training on data | ✅ Guaranteed by U-M | Critical for research |
| API integration | ✅ Azure OpenAI compatible | Easy migration |
| Research support | ✅ Designed for researchers | Primary use case |
| Reproducibility | ✅ Private environment | Stable for publication |

### Cost Benefits (Potential)

- University pricing may be more favorable than direct OpenAI/Anthropic APIs
- Single billing through Shortcode (simplified accounting)
- Real-time usage monitoring (better cost control)
- Predictable environment for reproducible research

### Technical Benefits

- Private cloud ensures consistent API availability
- Azure OpenAI compatible (minimal code changes)
- U-M support team for technical issues
- Integration with U-M research infrastructure

### Compliance Benefits

- Meets U-M data handling policies
- FERPA compliance built-in
- No external third-party data sharing
- Appropriate for moderate sensitivity research data

---

## Risk Assessment

### Potential Challenges

1. **Shortcode Requirement**
   - Need departmental billing approval
   - May require faculty sponsor coordination
   - **Mitigation:** Request assistance in form, attend office hours

2. **Cost Uncertainty**
   - Per-token rates not publicly disclosed
   - 60K narrative production run cost unknown
   - **Mitigation:** Request cost estimates during consultation, run testing phase first

3. **API Differences**
   - May require code modifications for Azure OpenAI endpoints
   - **Mitigation:** Our modular architecture makes this manageable, test with small sample first

4. **Model Availability**
   - Claude 3.5 Haiku is listed, but not Claude 3.5 Sonnet (our current model)
   - **Mitigation:** Confirm model availability during consultation, evaluate Haiku performance

5. **Production Timeline**
   - Approval process timeline uncertain
   - **Mitigation:** Submit request promptly, use existing APIs as backup

### Risk Mitigation Strategy

- Submit request while continuing to use existing OpenAI/Anthropic APIs
- Run parallel testing with UM-GPT once approved
- Compare results, costs, and performance before full migration
- Maintain dual API capability in codebase for flexibility

---

## Questions to Ask During Consultation

### Technical Questions

1. What are the exact API endpoints for GPT-4o and Claude 3.5 Haiku?
2. Is the API compatible with OpenAI Python SDK or OpenRouter-style interfaces?
3. What rate limits apply to API access?
4. Is Claude 3.5 Sonnet available? (Our current model)
5. Can we access o3-mini for reasoning-enhanced experiments?

### Cost Questions

6. What are the per-token rates for GPT-4o, Claude 3.5 Haiku, and o3-mini?
7. Can you provide a cost estimate for processing 60,000 narratives (~500 tokens each)?
8. Are there volume discounts or research pricing available?
9. How are costs tracked and reported in the Tableau dashboard?
10. What is the billing cycle and payment process?

### Operational Questions

11. How long does approval typically take?
12. How do we create and manage API keys?
13. Who has access to the Tableau dashboard?
14. Can we add team members to the project?
15. What support is available for technical issues?

### Data Questions

16. Confirm: Our deidentified narratives meet moderate sensitivity standards?
17. Are there any additional data handling requirements?
18. Can results be exported for publication?
19. Are there any restrictions on publishing findings?

---

## Implementation Plan (Post-Approval)

### Phase 1: Setup and Testing (Week 1-2)

- [ ] Receive API access and credentials
- [ ] Access GitHub documentation and examples
- [ ] Create test API keys
- [ ] Configure `.env` file with UM-GPT endpoints
- [ ] Update `R/call_llm.R` to support UM-GPT endpoints
- [ ] Run unit tests to verify integration
- [ ] Test with 10 sample narratives
- [ ] Verify result parsing and logging

### Phase 2: Validation Testing (Week 3-4)

- [ ] Run 404 narrative test set with GPT-4o via UM-GPT
- [ ] Run 404 narrative test set with Claude 3.5 Haiku via UM-GPT
- [ ] Compare results to baseline OpenAI/Anthropic API results
- [ ] Evaluate metrics (F1, precision, recall)
- [ ] Analyze cost per narrative
- [ ] Review Tableau dashboard usage data
- [ ] Identify any performance or accuracy differences

### Phase 3: Production Decision (Week 5)

- [ ] Review validation results
- [ ] Calculate projected costs for 60K narratives
- [ ] Compare to existing API costs
- [ ] Make go/no-go decision for production run
- [ ] If approved: Configure production run parameters

### Phase 4: Production Run (Week 6-8)

- [ ] Run full 60,000 narrative production set
- [ ] Monitor usage and costs in real-time
- [ ] Verify result quality
- [ ] Export results to PostgreSQL
- [ ] Generate publication-ready metrics
- [ ] Document methodology for paper

---

## Success Criteria

Our UM-GPT integration will be considered successful if:

1. ✅ **Equivalent or Better Accuracy**
   - F1, precision, recall within 2% of current API results
   - No significant degradation in detection quality

2. ✅ **Cost Efficiency**
   - Competitive or better pricing vs. direct OpenAI/Anthropic APIs
   - Predictable costs through dashboard monitoring

3. ✅ **Technical Stability**
   - Reliable API availability (>99% uptime)
   - Consistent response times
   - No data loss or corruption

4. ✅ **Reproducibility**
   - Consistent results across multiple runs
   - Stable environment for publication
   - Full audit trail for peer review

5. ✅ **Compliance**
   - Meets all U-M data handling policies
   - Appropriate for deidentified research data
   - No privacy or security concerns

---

## Conclusion

UM-GPT appears to be an **excellent fit** for our IPV detection research project:

- **Privacy-aligned**: Supports moderate sensitivity data, our narratives are fully deidentified
- **Model access**: Provides GPT-4o and Claude 3.5 Haiku (our primary needs)
- **Research-focused**: Designed for exactly this type of academic project
- **Cost-controlled**: Built-in monitoring and U-M pricing
- **Compliant**: Meets university data policies and research standards
- **Stable**: Private U-M environment ideal for reproducible research

**Recommendation:** Submit API access request promptly. UM-GPT could provide a more cost-effective, compliant, and stable platform for our production run of 60,000 narratives compared to direct commercial APIs.

---

**Document Version:** 1.0
**Last Updated:** October 17, 2025
**Next Review:** After API access approval
