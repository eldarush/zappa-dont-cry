# free-for.dev

Developers and Open Source authors now have many services offering free tiers, but finding them all takes time to make informed decisions.

This is a list of software (SaaS, PaaS, IaaS, etc.) and other offerings with free developer tiers.

The scope of this particular list is limited to things that infrastructure developers (System Administrator, DevOps Practitioners, etc.) are likely to find useful. We love all the free services out there, but it would be good to keep it on topic. It's a grey line sometimes, so this is opinionated; please don't feel offended if I don't accept your contribution.

This list results from Pull Requests, reviews, ideas, and work done by 1600+ people. You can also help by sending [Pull Requests](https://github.com/ripienaar/free-for-dev) to add more services or remove ones whose offerings have changed or been retired.

[![Track Awesome List](https://www.trackawesomelist.com/badge.svg)](https://www.trackawesomelist.com/ripienaar/free-for-dev)

**NOTE**: This list is only for as-a-Service offerings, not for self-hosted software. To be eligible, a service must offer a free tier, not just a free trial. The free tier must be for at least a year if it is time-bucketed. We also consider the free tier from a security perspective, so SSO is fine, but I will not accept services that restrict TLS to paid-only tiers.

# Table of Contents

  * [Major Cloud Providers' Always-Free Limits](#major-cloud-providers)
  * [Cloud management solutions](#cloud-management-solutions)
  * [Analytics, Events, and Statistics](#analytics-events-and-statistics)
  * [APIs, Data and ML](#apis-data-and-ml)
  * [Artifact Repos](#artifact-repos)
  * [BaaS](#baas)
  * [Low-code Platform](#low-code-platform)
  * [CDN and Protection](#cdn-and-protection)
  * [CI and CD](#ci-and-cd)
  * [CMS](#cms)
  * [Code Generation](#code-generation)
  * [Code Quality](#code-quality)
  * [Code Search and Browsing](#code-search-and-browsing)
  * [Crash and Exception Handling](#crash-and-exception-handling)
  * [Data Visualization on Maps](#data-visualization-on-maps)
  * [Managed Data Services](#managed-data-services)
  * [Design and UI](#design-and-ui)
  * [Dev Blogging Sites](#dev-blogging-sites)
  * [DNS](#dns)
  * [Docker Related](#docker-related)
  * [Domain](#domain)
  * [Education and Career Development](#education-and-career-development)
  * [Email](#email)
  * [Feature Toggles Management Platforms](#feature-toggles-management-platforms)
  * [Font](#font)
  * [Forms](#forms)
  * [Generative AI](#generative-ai)
  * [IaaS](#iaas)
  * [IDE and Code Editing](#ide-and-code-editing)
  * [International Mobile Number Verification API and SDK](#international-mobile-number-verification-api-and-sdk)
  * [Issue Tracking and Project Management](#issue-tracking-and-project-management)
  * [Log Management](#log-management)
  * [Mobile App Distribution and Feedback](#mobile-app-distribution-and-feedback)
  * [Management Systems](#management-system)
  * [Messaging and Streaming](#messaging-and-streaming)
  * [Miscellaneous](#miscellaneous)
  * [Monitoring](#monitoring)
  * [PaaS](#paas)
  * [Package Build System](#package-build-system)
  * [Payment and Billing Integration](#payment-and-billing-integration)
  * [Privacy Management](#privacy-management)
  * [Screenshot APIs](#screenshot-apis)
  * [Flutter Related and Building IOS Apps without Mac](#flutter-related-and-building-ios-apps-without-mac)
  * [Search](#search)
  * [Security and PKI](#security-and-pki)
  * [Authentication, Authorization, and User Management](#authentication-authorization-and-user-management)
  * [Source Code Repos](#source-code-repos)
  * [Storage and Media Processing](#storage-and-media-processing)
  * [Tunneling, WebRTC, Web Socket Servers and Other Routers](#tunneling-webrtc-web-socket-servers-and-other-routers)
  * [Testing](#testing)
  * [Tools for Teams and Collaboration](#tools-for-teams-and-collaboration)
  * [Translation Management](#translation-management)
  * [Visitor Session Recording](#visitor-session-recording)
  * [Web Hosting](#web-hosting)
  * [Commenting Platforms](#commenting-platforms)
  * [Browser based hardware emulation](#browser-based-hardware-emulation-written-in-javascript)
  * [Remote Desktop Tools](#remote-desktop-tools)
  * [Other Free Resources](#other-free-resources)

## Major Cloud Providers

  * [Google Cloud Platform](https://cloud.google.com)
    * App Engine - 28 frontend instance hours per day, nine backend instance hours per day
    * Cloud Firestore - 1GB storage, 50,000 reads, 20,000 writes, 20,000 deletes per day
    * Compute Engine - 1 non-preemptible e2-micro, 30GB HDD, 5GB snapshot storage (restricted to certain regions), 1 GB network egress from North America to all region destinations (excluding China and Australia) per month
    * Cloud Storage - 5GB, 1GB network egress
    * Cloud Shell - Web-based Linux shell/primary IDE with 5GB of persistent storage. 60 hours limit per week
    * Cloud Pub/Sub - 10GB of messages per month
    * Cloud Functions - 2 million invocations per month (includes both background and HTTP invocations)
    * Cloud Run - 2 million requests per month, 360,000 GB-seconds memory, 180,000 vCPU-seconds of compute time, 1 GB network egress from North America per month
    * Google Kubernetes Engine - No cluster management fee for one zonal cluster. Each user node is charged at standard Compute Engine pricing
    * BigQuery - 1 TB of querying per month, 10 GB of storage each month
    * Cloud Build - 120 build-minutes per day
    * [Google Colab](https://colab.research.google.com/) - Free Jupyter Notebooks development environment.
    * [Kaggle](https://www.kaggle.com/) - Jupyter Notebooks with 4 CPU cores and 30 GB RAM computational environment without any weekly usage limits. With Phone number verification - 1 Nvidia Tesla P100 GPU or 2x Nvidia Tesla T4 GPU can be added with usage limit of 30 GPU hours/week for free. With Identity verification - 1 TPU v3-8 with 96 CPU cores and 330 GB RAM is available with usage limit of 20 hours/week for free. Check [Technical Specifications](https://www.kaggle.com/docs/notebooks#technical-specifications) for more details.
    * Full, detailed list - https://cloud.google.com/free

  * [Amazon Web Services](https://aws.amazon.com)
    * [CloudFront](https://aws.amazon.com/cloudfront/) - 1TB egress per month and 2M Function invocations per month
    * [CloudWatch](https://aws.amazon.com/cloudwatch/) - 10 custom metrics and ten alarms
    * [CodeBuild](https://aws.amazon.com/codebuild/) - 100min of build time per month
    * [CodeCommit](https://aws.amazon.com/codecommit/) - 5 active users,50GB storage, and 10000 requests per month
    * [CodePipeline](https://aws.amazon.com/codepipeline/) - 1 active pipeline per month
    * [DynamoDB](https://aws.amazon.com/dynamodb/) - 25GB NoSQL DB
    * [EC2](https://aws.amazon.com/ec2/) - 750 hours per month of t2.micro or t3.micro(12mo). 100GB egress per month
    * [EBS](https://aws.amazon.com/ebs/) - 30GB per month of General Purpose (SSD) or Magnetic(12mo)
    * [Elastic Load Balancing](https://aws.amazon.com/elasticloadbalancing/) - 750 hours per month(12mo)
    * [RDS](https://aws.amazon.com/rds/) - 750 hours per month of db.t2.micro, db.t3.micro, or db.t4g.micro, 20GB of General Purpose (SSD) storage, 20GB of storage backups(12 mo)
    * [S3](https://aws.amazon.com/s3/) - 5GB Standard object storage, 20K Get requests and 2K Put requests(12 mo)
    * [Glacier](https://aws.amazon.com/glacier/) - 10GB long-term object storage
    * [Lambda](https://aws.amazon.com/lambda/) - 1 million requests per month
    * [SNS](https://aws.amazon.com/sns/) - 1 million publishes per month
    * [SES](https://aws.amazon.com/ses/) - 3.000 messages per month (12mo)
    * [SQS](https://aws.amazon.com/sqs/) - 1 million messaging queue requests
    * Full, detailed list - https://aws.amazon.com/free/

  * [Microsoft Azure](https://azure.microsoft.com)
    * [Virtual Machines](https://azure.microsoft.com/services/virtual-machines/) - 1 B1S Linux VM, 1 B1S Windows VM (12mo)
    * [App Service](https://azure.microsoft.com/services/app-service/) - 10 web, mobile, or API apps (60 CPU minutes/day)
    * [Functions](https://azure.microsoft.com/services/functions/) - 1 million requests per month
    * [DevTest Labs](https://azure.microsoft.com/services/devtest-lab/) - Enable fast, easy, and lean dev-test environments
    * [Active Directory](https://azure.microsoft.com/services/active-directory/) - 500,000 objects
    * [Active Directory B2C](https://azure.microsoft.com/services/active-directory/external-identities/b2c/) - 50,000 monthly stored users
    * [Azure DevOps](https://azure.microsoft.com/services/devops/) - 5 active users, unlimited private Git repos
    * [Azure Pipelines](https://azure.microsoft.com/services/devops/pipelines/) - 10 free parallel jobs with unlimited minutes for open source for Linux, macOS, and Windows
    * [Microsoft IoT Hub](https://azure.microsoft.com/services/iot-hub/) - 8,000 messages per day
    * [Load Balancer](https://azure.microsoft.com/services/load-balancer/) - 1 free public load-balanced IP (VIP)
    * [Notification Hubs](https://azure.microsoft.com/services/notification-hubs/) - 1 million push notifications
    * [Bandwidth](https://azure.microsoft.com/pricing/details/bandwidth/) - 15GB Inbound(12mo) & 5GB egress per month
    * [Cosmos DB](https://azure.microsoft.com/services/cosmos-db/) - 25GB storage and 1000 RUs of provisioned throughput
    * [Static Web Apps](https://azure.microsoft.com/pricing/details/app-service/static/) - Build, deploy, and host static apps and serverless functions with free SSL, Authentication/Authorization, and custom domains
    * [Storage](https://azure.microsoft.com/services/storage/) - 5GB LRS File or Blob storage (12mo)
    * [Cognitive Services](https://azure.microsoft.com/services/cognitive-services/) - AI/ML APIs (Computer Vision, Translator, Face detection, Bots, etc) with free tier including limited transactions
    * [Cognitive Search](https://azure.microsoft.com/services/search/#features) - AI-based search and indexation service, free for 10,000 documents
    * [Azure Kubernetes Service](https://azure.microsoft.com/services/kubernetes-service/) - Managed Kubernetes service, free cluster management
    * [Event Grid](https://azure.microsoft.com/services/event-grid/) - 100K ops/month
    * Full, detailed list - https://azure.microsoft.com/free/

  * [Oracle Cloud](https://www.oracle.com/cloud/)
    * Compute
       - 2 AMD-based Compute VMs with 1/8 OCPU and 1 GB memory each
       - 4 Arm-based Ampere A1 cores and 24 GB of memory usable as one VM or up to 4 VMs
       - Instances will be reclaimed when [deemed idle](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm#compute__idleinstances)
    * Block Volume - 2 volumes, 200 GB total (used for compute)
    * Object Storage - 10 GB
    * Load balancer - 1 instance with 10 Mbps
    * Databases - 2 DBs, 20 GB each
    * Monitoring - 500 million ingestion data points, 1 billion retrieval datapoints
    * Bandwidth - 10 TB egress per month, speed limited to 50 Mbps on x64-based VM, 500 Mbps * core count on ARM-based VM
    * Public IP - 2 IPv4 for VMs, 1 IPv4 for load balancer
    * Notifications - 1 million delivery options per month, 1000 emails sent per month
    * Full, detailed list - https://www.oracle.com/cloud/free/

  * [IBM Cloud](https://www.ibm.com/cloud/free/)
    * Cloudant database - 1 GB of data storage
    * Db2 database - 100MB of data storage
    * API Connect - 50,000 API calls per month
    * Availability Monitoring - 3 million data points per month
    * Log Analysis - 500MB of daily log
    * Full, detailed list - https://www.ibm.com/cloud/free/

  * [Cloudflare](https://www.cloudflare.com/)
    * [Application Services](https://www.cloudflare.com/plans/) - Free DNS for an unlimited number of domains, DDoS Protection, CDN along with free SSL, Firewall rules and page rules,  WAF, Bot Mitigation, Free Unmetered Rate Limiting - 1 rule per domain, Analytics, Email forwarding
    * [Zero Trust & SASE](https://www.cloudflare.com/plans/zero-trust-services/) - Up to 50 Users, 24 hours of activity logging, three network locations
    * [Cloudflare Tunnel](https://www.cloudflare.com/products/tunnel/) -  You can expose locally running HTTP port over a tunnel to a random subdomain on trycloudflare.com use [Quick Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/do-more-with-tunnels/trycloudflare/), No account required. More features (TCP tunnel, Load balancing, VPN) in [Zero Trust](https://www.cloudflare.com/products/zero-trust/) Free Plan.
    * [Workers](https://developers.cloudflare.com/workers/) - Deploy serverless code for free on Cloudflare's global network-100k daily requests.
    * [Workers KV](https://developers.cloudflare.com/kv) - 100k read requests per day, 1000 write requests per day, 1000 delete requests per day, 1000 list requests per day, 1 GB stored data
    * [R2](https://developers.cloudflare.com/r2/) - 10 GB per month, 1 million Class A operations per month, 10 million Class B operations per month
    * [D1](https://developers.cloudflare.com/d1/) - 5 million rows read per day, 100k rows written per day, 1 GB storage
    * [Pages](https://developers.cloudflare.com/pages/) - Develop and deploy your web apps on Cloudflare's fast, secure global network. Five hundred monthly builds, 100 custom domains, Integrated SSL, unlimited accessible seats, unlimited preview deployments, and full-stack capability via Cloudflare Workers integration.
    * [Queues](https://developers.cloudflare.com/queues/) - 1 million operations per month
    * [TURN](https://developers.cloudflare.com/calls/turn/) - 1TB of free (outgoing) traffic per month.

  * [Zoho](https://www.zoho.com) - Started as an e-mail provider but now provides a suite of services, some of which have free plans. List of services having free plans :
    * [Catalyst by Zoho](https://catalyst.zoho.com) -  PaaS/full-stack cloud platform with a generous [free tier](https://catalyst.zoho.com/free-tier.html)
    * [Email](https://zoho.com/mail) Free for 5 users. 5GB/user & 25 MB attachment limit, one domain.
    * [Zoho Assist](https://www.zoho.com/assist) - Zoho Assist's forever free plan includes one concurrent remote support license and Access to 5 unattended computer licenses for unlimited duration available for both professional and personnel use.
    * [Sprints](https://zoho.com/sprints) Free for 5 users,5 Projects & 500MB storage.
    * [Docs](https://zoho.com/docs) - Free for 5 users with 1 GB upload limit & 5GB storage. Zoho Office Suite (Writer, Sheets & Show) comes bundled.
    * [Projects](https://zoho.com/projects) - Free for 3 users, 2 projects & 10 MB attachment limit. The same plan applies to [Bugtracker](https://zoho.com/bugtracker).
    * [Connect](https://zoho.com/connect) - Team Collaboration free for 25 users with three groups, three custom apps, 3 Boards, 3 Manuals, and 10 Integrations along with channels, events & forums.
    * [Meeting](https://zoho.com/meeting) - Meetings with upto 3 meeting participants & 10 Webinar attendees.
    * [Vault](https://zoho.com/vault) - Password Management is accessible for Individuals.
    * [Showtime](https://zoho.com/showtime) - Yet another Meeting software for training for a remote session of up to 5 attendees.
    * [Notebook](https://zoho.com/notebook) - A free alternative to Evernote.
    * [Wiki](https://zoho.com/wiki) - Free for three users with 50 MB storage, unlimited pages, zip backups, RSS & Atom feed, access controls & customizable CSS.
    * [Subscriptions](https://zoho.com/subscriptions) - Recurring Billing management free for 20 customers/subscriptions & 1 user with all the payment hosting done by Zoho. The last 40 subscription metrics are stored
    * [Checkout](https://zoho.com/checkout) - Product Billing management with 3 pages & up to 50 payments.
    * [Desk](https://zoho.com/desk) - Customer Support management with three agents, private knowledge base, and email tickets. Integrates with [Assist](https://zoho.com/assist) for one remote technician & 5 unattended computers.
    * [Cliq](https://zoho.com/cliq) - Team chat software with 100 GB storage, unlimited users, 100 users per channel & SSO.
    * [Campaigns](https://zoho.com/campaigns) - Email Marketing
    * [Forms](https://zoho.com/forms) - Form Creator
    * [Sign](https://zoho.com/sign) - Paperless Signatures
    * [Surveys](https://zoho.com/surveys) - Online Surveys
     * [Bookings](https://zoho.com/bookings) - Appointment Scheduling

**[⬆️ Back to Top](#table-of-contents)**

## Cloud management solutions

  * [Brainboard](https://www.brainboard.co) - Collaborative solution to visually build and manage cloud infrastructures from end-to-end.
  * [Cloud 66](https://www.cloud66.com/) - Free for personal projects (includes one deployment server, one static site), Cloud 66 gives you everything you need to build, deploy, and grow your applications on any cloud without the headache of the “server stuff.”.
  * [deployment.io](https://deployment.io) - Deployment.io helps developers automate deployments on AWS. On our free tier, a developer (single user) can deploy unlimited static sites, web services, and environments. We provide 10 job executions free per month with previews and auto-deploys included in the free tier.
  * [Pulumi](https://www.pulumi.com/) - Modern infrastructure as a code platform that allows you to use familiar programming languages and tools to build, deploy, and manage cloud infrastructure.
  * [scalr.com](https://scalr.com/) - Scalr is a Terraform Automation and COllaboration (TACO) product used to better collaboration and automation on infrastructure and configurations managed by Terraform. Full Terraform CLI support, OPA integration, and a hierarchical configuration model. No SSO tax. All features are included. Use up to 50 runs/month for free.

**[⬆️ Back to Top](#table-of-contents)**

## Source Code Repos

  * [Bitbucket](https://bitbucket.org/) - Unlimited public and private Git repos for up to 5 users with Pipelines for CI/CD
  * [Codeberg](https://codeberg.org/) - Unlimited public and private Git repos for free and open-source projects (with unlimited collaborators). Powered by [Forgejo](https://forgejo.org/). Static website hosting with [Codeberg Pages](https://codeberg.page/). CI/CD hosting with [Codeberg's CI](https://docs.codeberg.org/ci/). Translating hosting with [Codeberg Translate](https://translate.codeberg.org/). Includes Package and Container hosting, Project management, and Issue Tracking
  * [framagit.org](https://framagit.org/) - Framagit is the software forge of Framasoft based on the Gitlab software includes CI, Static Pages, Project pages and Issue tracking.
  * [GitGud](https://gitgud.io) - Unlimited private and public repositories. Free forever. Powered by GitLab & Sapphire. Includes CI/CD, Static Hosting, Container Registry, Project Management and Issue Tracking.
  * [GitHub](https://github.com/) - Unlimited public repositories and unlimited private repositories (with unlimited collaborators). Includes CI/CD, Development Environment, Static Hosting, Package and Container hosting, Project management and AI Copilot
  * [gitlab.com](https://about.gitlab.com/) - Unlimited public and private Git repos with up to 5 collaborators. Includes CI/CD, Static Hosting, Container Registry, Project Management and Issue Tracking
  * [heptapod.net](https://foss.heptapod.net/) - Heptapod is a friendly fork of GitLab Community Edition providing support for Mercurial
  * [pijul.com](https://pijul.com/) - Unlimite
