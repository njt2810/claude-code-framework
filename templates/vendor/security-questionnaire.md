# Vendor Security Questionnaire (Outbound)

Use this when YOU send a questionnaire to a vendor you're considering.

Vendor: {{VENDOR}}
Sent: {{DATE}}
Owner: {{REQUESTOR}}

## Company Information

1. Legal name and HQ jurisdiction
2. Year founded
3. Number of employees
4. Funding stage (if relevant)

## Certifications and Compliance

5. SOC 2 Type 1 or Type 2? Last report date? Can you share it under NDA?
6. ISO 27001 certified? Last audit date?
7. GDPR compliance posture?
8. PDPA compliance posture?
9. Other relevant certifications (PCI-DSS, HIPAA, etc.)?

## Data Handling

10. What data of ours will you process?
11. Where (region) is data stored?
12. Is data encrypted at rest? With what algorithm and key management?
13. Is data encrypted in transit? TLS version required?
14. Who has access to our data on your side? Background checks performed?
15. Sub-processors: please list, with their function

## Security Practices

16. How do you handle vulnerability disclosure?
17. Penetration test cadence? Last test date?
18. Bug bounty program?
19. Patch SLA for critical vulnerabilities?
20. MFA enforced for your personnel accessing customer data?

## Incident Response

21. Breach notification SLA?
22. Has there been a security incident in the past 24 months? Details (under NDA)?
23. Incident response plan documented?

## Contract Terms

24. DPA available for review?
25. Will you sign our DPA, or do you require yours?
26. Data deletion on contract termination?
27. Data export format and timeline?
28. Audit rights?

## Operational

29. Uptime SLA?
30. Status page URL?
31. Support response SLA?
32. Geographic redundancy?

## Pricing (if not already known)

33. Pricing model (per-user, per-event, fixed)?
34. Contract length and termination terms?
35. Price escalation cap on renewal?

---

# Vendor Security Questionnaire (Inbound)

Use this when a client sends YOU a questionnaire. Pull answers from project documentation.

Client: {{CLIENT}}
Received: {{DATE}}
Owner: {{RESPONDER}}
Due back: {{DUE_DATE}}

## How to Respond

For each question, the answer comes from one of:
- `wiki/compliance/policies/` — security policies
- `wiki/compliance/data-inventory.md` — what PII you process
- `wiki/compliance/vendor-register.md` — sub-processors
- `wiki/compliance/audit-logging.md` — audit logging
- `wiki/operations/incident-response.md` — IR plan
- `wiki/operations/disaster-recovery.md` — DR plan
- `wiki/compliance/evidence/` — SOC 2 evidence
- `wiki/conventions.md` — coding/auth conventions

If a question asks about a control you haven't implemented yet:
- Answer "Not yet implemented — planned for {date}"
- Add the gap to `wiki/compliance/gaps.md`
- Run `/compliance-audit` to update gap status
- Do NOT lie — auditors and clients will discover

Save your response as `wiki/compliance/questionnaires/{client}-{date}.md`.
