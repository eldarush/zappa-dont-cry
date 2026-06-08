[✔]: assets/images/checkbox-small-blue.png

# Node.js Best Practices

<h1 align="center">
  <img src="assets/images/banner-2.jpg" alt="Node.js Best Practices"/>
</h1>

<br/>

<div align="center">
  <img src="https://img.shields.io/badge/⚙%20Item%20count%20-%20102%20Best%20Practices-blue.svg" alt="102 items"/> <img id="last-update-badge" src="https://img.shields.io/badge/%F0%9F%93%85%20Last%20update%20-%20January%2024%2C%202023-green.svg" alt="Last update: January 3rd, 2024" /> <img src="https://img.shields.io/badge/ %E2%9C%94%20Updated%20For%20Version%20-%20Node%2022.0.0-brightgreen.svg" alt="Updated for Node 22.0.0"/>
</div>

<br/>

[<img src="assets/images/twitter.svg" width="16" height="16" alt="" />](https://twitter.com/nodepractices/) **Follow us on Twitter!** [**@nodepractices**](https://twitter.com/nodepractices/)

<br/>

Read in a different language: [![CN](./assets/flags/CN.png)**CN**](./README.chinese.md), [![FR](./assets/flags/FR.png)**FR**](./README.french.md), [![BR](./assets/flags/BR.png)**BR**](./README.brazilian-portuguese.md), [![RU](./assets/flags/RU.png)**RU**](./README.russian.md), [![PL](./assets/flags/PL.png)**PL**](./README.polish.md), [![JA](./assets/flags/JA.png)**JA**](./README.japanese.md), [![EU](./assets/flags/EU.png)**EU**](./README.basque.md) [(![ES](./assets/flags/ES.png)**ES**, ![HE](./assets/flags/HE.png)**HE**, ![KR](./assets/flags/KR.png)**KR** and ![TR](./assets/flags/TR.png)**TR** in progress! )](#translations)

<br/>

# 🎊 2024 edition is here!

- **🛰 Modernized to 2024**: Tons of text edits, new recommended libraries, and some new best practices

- **✨ Easily focus on new content**: Already visited before? Search for `#new` or `#updated` tags for new content only

- **🔖 Curious to see examples? We have a starter**: Visit [Practica.js](https://github.com/practicajs/practica), our application example and boilerplate (beta) to see some practices in action

<br/><br/>

# Welcome! 3 Things You Ought To Know First

**1. You are reading dozens of the best Node.js articles -** this repository is a summary and curation of the top-ranked content on Node.js best practices, as well as content written here by collaborators

**2. It is the largest compilation, and it is growing every week -** currently, more than 80 best practices, style guides, and architectural tips are presented. New issues and pull requests are created every day to keep this live book updated. We'd love to see you contributing here, whether that is fixing code mistakes, helping with translations, or suggesting brilliant new ideas. See our [writing guidelines here](./.operations/writing-guidelines.md)

**3. Best practices have additional info -** most bullets include a **🔗Read More** link that expands on the practice with code examples, quotes from selected blogs, and more information

<br/><br/>

# By Yoni Goldberg

### Learn with me: As a consultant, I engage with worldwide teams on various activities like workshops and code reviews. 🎉AND... Hold on, I've just launched my [beyond-the-basics testing course, which is on a 🎁 limited-time sale](https://testjavascript.com/) until August 7th

<br/><br/>

## Table of Contents

<details>
  <summary>
    <a href="#1-project-architecture-practices">1. Project Architecture Practices (6)</a>
  </summary>

&emsp;&emsp;[1.1 Structure your solution by components `#strategic` `#updated`](#-11-structure-your-solution-by-business-components)</br>
&emsp;&emsp;[1.2 Layer your components, keep the web layer within its boundaries `#strategic` `#updated`](#-12-layer-your-components-with-3-tiers-keep-the-web-layer-within-its-boundaries)</br>
&emsp;&emsp;[1.3 Wrap common utilities as packages, consider publishing](#-13-wrap-common-utilities-as-packages-consider-publishing)</br>
&emsp;&emsp;[1.4 Use environment aware, secure and hierarchical config `#updated`](#-14-use-environment-aware-secure-and-hierarchical-config)</br>
&emsp;&emsp;[1.5 Consider all the consequences when choosing the main framework `#new`](#-15-consider-all-the-consequences-when-choosing-the-main-framework)</br>
&emsp;&emsp;[1.6 Use TypeScript sparingly and thoughtfully `#new`](#-16-use-typescript-sparingly-and-thoughtfully)</br>

</details>

<details>
  <summary>
    <a href="#2-error-handling-practices">2. Error Handling Practices (12)</a>
  </summary>

&emsp;&emsp;[2.1 Use Async-Await or promises for async error handling](#-21-use-async-await-or-promises-for-async-error-handling)</br>
&emsp;&emsp;[2.2 Extend the built-in Error object `#strategic` `#updated`](#-22-extend-the-built-in-error-object)</br>
&emsp;&emsp;[2.3 Distinguish operational vs programmer errors `#strategic` `#updated`](#-23-distinguish-catastrophic-errors-from-operational-errors)</br>
&emsp;&emsp;[2.4 Handle errors centrally, not within a middleware `#strategic`](#-24-handle-errors-centrally-not-within-a-middleware)</br>
&emsp;&emsp;[2.5 Document API errors using OpenAPI or GraphQL](#-25-document-api-errors-using-openapi-or-graphql)</br>
&emsp;&emsp;[2.6 Exit the process gracefully when a stranger comes to town `#strategic`](#-26-exit-the-process-gracefully-when-a-stranger-comes-to-town)</br>
&emsp;&emsp;[2.7 Use a mature logger to increase errors visibility `#updated`](#-27-use-a-mature-logger-to-increase-errors-visibility)</br>
&emsp;&emsp;[2.8 Test error flows using your favorite test framework `#updated`](#-28-test-error-flows-using-your-favorite-test-framework)</br>
&emsp;&emsp;[2.9 Discover errors and downtime using APM products](#-29-discover-errors-and-downtime-using-apm-products)</br>
&emsp;&emsp;[2.10 Catch unhandled promise rejections `#updated`](#-210-catch-unhandled-promise-rejections)</br>
&emsp;&emsp;[2.11 Fail fast, validate arguments using a dedicated library](#-211-fail-fast-validate-arguments-using-a-dedicated-library)</br>
&emsp;&emsp;[2.12 Always await promises before returning to avoid a partial stacktrace `#new`](#-212-always-await-promises-before-returning-to-avoid-a-partial-stacktrace)</br>
&emsp;&emsp;[2.13 Subscribe to event emitters 'error' event `#new`](#-213-subscribe-to-event-emitters-and-streams-error-event)</br>

</details>

<details>
  <summary>
    <a href="#3-code-patterns-and-style-practices">3. Code Style Practices (12)</a>
  </summary>

&emsp;&emsp;[3.1 Use ESLint `#strategic`](#-31-use-eslint)</br>
&emsp;&emsp;[3.2 Use Node.js eslint extension plugins `#updated`](#-32-use-nodejs-eslint-extension-plugins)</br>
&emsp;&emsp;[3.3 Start a Codeblock's Curly Braces on the Same Line](#-33-start-a-codeblocks-curly-braces-on-the-same-line)</br>
&emsp;&emsp;[3.4 Separate your statements properly](#-34-separate-your-statements-properly)</br>
&emsp;&emsp;[3.5 Name your functions](#-35-name-your-functions)</br>
&emsp;&emsp;[3.6 Use naming conventions for variables, constants, functions and classes](#-36-use-naming-conventions-for-variables-constants-functions-and-classes)</br>
&emsp;&emsp;[3.7 Prefer const over let. Ditch the var](#-37-prefer-const-over-let-ditch-the-var)</br>
&emsp;&emsp;[3.8 Require modules first, not inside functions](#-38-require-modules-first-not-inside-functions)</br>
&emsp;&emsp;[3.9 Set an explicit entry point to a module/folder `#updated`](#-39-set-an-explicit-entry-point-to-a-modulefolder)</br>
&emsp;&emsp;[3.10 Use the === operator](#-310-use-the--operator)</br>
&emsp;&emsp;[3.11 Use Async Await, avoid callbacks `#strategic`](#-311-use-async-await-avoid-callbacks)</br>
&emsp;&emsp;[3.12 Use arrow function expressions (=>)](#-312-use-arrow-function-expressions-)</br>
&emsp;&emsp;[3.13 Avoid effects outside of functions `#new`](#-313-avoid-effects-outside-of-functions)</br>

</details>

<details>
  <summary>
    <a href="#4-testing-and-overall-quality-practices">4. Testing And Overall Quality Practices (13)</a>
  </summary>

&emsp;&emsp;[4.1 At the very least, write API (component) testing `#strategic`](#-41-at-the-very-least-write-api-component-testing)</br>
&emsp;&emsp;[4.2 Include 3 parts in each test name `#new`](#-42-include-3-parts-in-each-test-name)</br>
&emsp;&emsp;[4.3 Structure tests by the AAA pattern `#strategic`](#-43-structure-tests-by-the-aaa-pattern)</br>
&emsp;&emsp;[4.4 Ensure Node version is unified `#new`](#-44-ensure-node-version-is-unified)</br>
&emsp;&emsp;[4.5 Avoid global test fixtures and seeds, add data per-test `#strategic`](#-45-avoid-global-test-fixtures-and-seeds-add-data-per-test)</br>
&emsp;&emsp;[4.6 Tag your tests `#advanced`](#-46-tag-your-tests)</br>
&emsp;&emsp;[4.7 Check your test coverage, it helps to identify wrong test patterns](#-47-check-your-test-coverage-it-helps-to-identify-wrong-test-patterns)</br>
&emsp;&emsp;[4.8 Use production-like environment for e2e testing](#-48-use-production-like-environment-for-e2e-testing)</br>
&emsp;&emsp;[4.9 Refactor regularly using static analysis tools](#-49-refactor-regularly-using-static-analysis-tools)</br>
&emsp;&emsp;[4.10 Mock responses of external HTTP services #advanced `#new` `#advanced`](#-410-mock-responses-of-external-http-services)</br>
&emsp;&emsp;[4.11 Test your middlewares in isolation](#-411-test-your-middlewares-in-isolation)</br>
&emsp;&emsp;[4.12 Specify a port in production, randomize in testing `#new`](#-412-specify-a-port-in-production-randomize-in-testing)</br>
&emsp;&emsp;[4.13 Test the five possible outcomes #strategic `#new`](#-413-test-the-five-possible-outcomes)</br>

</details>

<details>
  <summary>
    <a href="#5-going-to-production-practices">5. Going To Production Practices (19)</a>
  </summary>

&emsp;&emsp;[5.1. Monitoring `#strategic`](#-51-monitoring)</br>
&emsp;&emsp;[5.2. Increase the observability using smart logging `#strategic`](#-52-increase-the-observability-using-smart-logging)</br>
&emsp;&emsp;[5.3. Delegate anything possible (e.g. gzip, SSL) to a reverse proxy `#strategic`](#-53-delegate-anything-possible-eg-gzip-ssl-to-a-reverse-proxy)</br>
&emsp;&emsp;[5.4. Lock dependencies](#-54-lock-dependencies)</br>
&emsp;&emsp;[5.5. Guard process uptime using the right tool](#-55-guard-process-uptime-using-the-right-tool)</br>
&emsp;&emsp;[5.6. Utilize all CPU cores](#-56-utilize-all-cpu-cores)</br>
&emsp;&emsp;[5.7. Create a ‘maintenance endpoint’](#-57-create-a-maintenance-endpoint)</br>
&emsp;&emsp;[5.8. Discover the unknowns using APM products `#advanced` `#updated`](#-58-discover-the-unknowns-using-apm-products)</br>
&emsp;&emsp;[5.9. Make your code production-ready](#-59-make-your-code-production-ready)</br>
&emsp;&emsp;[5.10. Measure and guard the memory usage `#advanced`](#-510-measure-and-guard-the-memory-usage)</br>
&emsp;&emsp;[5.11. Get your frontend assets out of Node](#-511-get-your-frontend-assets-out-of-node)</br>
&emsp;&emsp;[5.12. Strive to be stateless `#strategic`](#-512-strive-to-be-stateless)</br>
&emsp;&emsp;[5.13. Use tools that automatically detect vulnerabilities](#-513-use-tools-that-automatically-detect-vulnerabilities)</br>
&emsp;&emsp;[5.14. Assign a transaction id to each log statement `#advanced`](#-514-assign-a-transaction-id-to-each-log-statement)</br>
&emsp;&emsp;[5.15. Set NODE_ENV=production](#-515-set-node_envproduction)</br>
&emsp;&emsp;[5.16. Design automated, atomic and zero-downtime deployments `#advanced`](#-516-design-automated-atomic-and-zero-downtime-deployments)</br>
&emsp;&emsp;[5.17. Use an LTS release of Node.js](#-517-use-an-lts-release-of-nodejs)</br>
&emsp;&emsp;[5.18. Log to stdout, avoid specifying log destination within the app `#updated`](#-518-log-to-stdout-avoid-specifying-log-destination-within-the-app)</br>
&emsp;&emsp;[5.19. Install your packages with npm ci `#new`](#-519-install-your-packages-with-npm-ci)</br>

</details>

<details>
  <summary>
    <a href="#6-security-best-practices">6. Security Practices (25)</a>
  </summary>

&emsp;&emsp;[6.1. Embrace linter security rules](#-61-embrace-linter-security-rules)</br>
&emsp;&emsp;[6.2. Limit concurrent requests using a middleware](#-62-limit-concurrent-requests-using-a-middleware)</br>
&emsp;&emsp;[6.3 Extract secrets from config files or use packages to encrypt them `#strategic`](#-63-extract-secrets-from-config-files-or-use-packages-to-encrypt-them)</br>
&emsp;&emsp;[6.4. Prevent query injection vulnerabilities with ORM/ODM libraries `#strategic`](#-64-prevent-query-injection-vulnerabilities-with-ormodm-libraries)</br>
&emsp;&emsp;[6.5. Collection of generic security best practices](#-65-collection-of-generic-security-best-practices)</br>
&emsp;&emsp;[6.6. Adjust the HTTP response headers for enhanced security](#-66-adjust-the-http-response-headers-for-enhanced-security)</br>
&emsp;&emsp;[6.7. Constantly and automatically inspect for vulnerable dependencies `#strategic`](#-67-constantly-and-automatically-inspect-for-vulnerable-dependencies)</br>
&emsp;&emsp;[6.8. Protect Users' Passwords/Secrets using bcrypt or scrypt `#strategic`](#-68-protect-users-passwordssecrets-using-bcrypt-or-scrypt)</br>
&emsp;&emsp;[6.9. Escape HTML, JS and CSS output](#-69-escape-html-js-and-css-output)</br>
&emsp;&emsp;[6.10. Validate incoming JSON schemas `#strategic`](#-610-validate-incoming-json-schemas)</br>
&emsp;&emsp;[6.11. Support blocklisting JWTs](#-611-support-blocklisting-jwts)</br>
&emsp;&emsp;[6.12. Prevent brute-force attacks against authorization `#advanced`](#-612-prevent-brute-force-attacks-against-authorization)</br>
&emsp;&emsp;[6.13. Run Node.js as non-root user](#-613-run-nodejs-as-non-root-user)</br>
&emsp;&emsp;[6.14. Limit payload size using a reverse-proxy or a middleware](#-614-limit-payload-size-using-a-reverse-proxy-or-a-middleware)</br>
&emsp;&emsp;[6.15. Avoid JavaScript eval statements](#-615-avoid-javascript-eval-statements)</br>
&emsp;&emsp;[6.16. Prevent evil RegEx from overloading your single thread execution](#-616-prevent-evil-regex-from-overloading-your-single-thread-execution)</br>
&emsp;&emsp;[6.17. Avoid module loading using a variable](#-617-avoid-module-loading-using-a-variable)</br>
&emsp;&emsp;[6.18. Run unsafe code in a sandbox](#-618-run-unsafe-code-in-a-sandbox)</br>
&emsp;&emsp;[6.19. Take extra care when working with child processes `#advanced`](#-619-take-extra-care-when-working-with-child-processes)</br>
&emsp;&emsp;[6.20. Hide error details from clients](#-620-hide-error-details-from-clients)</br>
&emsp;&emsp;[6.21. Configure 2FA for npm or Yarn `#strategic`](#-621-configure-2fa-for-npm-or-yarn)</br>
&emsp;&emsp;[6.22. Modify session middleware settings](#-622-modify-session-middleware-settings)</br>
&emsp;&emsp;[6.23. Avoid DOS attacks by explicitly setting when a process should crash `#advanced`](#-623-avoid-dos-attacks-by-explicitly-setting-when-a-process-should-crash)</br>
&emsp;&emsp;[6.24. Prevent unsafe redirects](#-624-prevent-unsafe-redirects)</br>
&emsp;&emsp;[6.25. Avoid publishing secrets to the npm registry](#-625-avoid-publishing-secrets-to-the-npm-registry)</br>
&emsp;&emsp;[6.26. 6.26 Inspect for outdated packages](#-626-inspect-for-outdated-packages)</br>
&emsp;&emsp;[6.27. Import built-in modules using the 'node:' protocol `#new`](#-627-import-built-in-modules-using-the-node-protocol)</br>

</details>

<details>
  <summary>
    <a href="#7-draft-performance-best-practices">7. Performance Practices (2) (Work In Progress️ ✍️)</a>
  </summary>

&emsp;&emsp;[7.1. Don't block the event loop](#-71-dont-block-the-event-loop)</br>
&emsp;&emsp;[7.2. Prefer native JS methods over user-land utils like Lodash](#-72-prefer-native-js-methods-over-user-land-utils-like-lodash)</br>

</details>

<details>
  <summary>
    <a href="#8-docker-best-practices">8. Docker Practices (15)</a>
  </summary>

&emsp;&emsp;[8.1 Use multi-stage builds for leaner and more secure Docker images `#strategic`](#-81-use-multi-stage-builds-for-leaner-and-more-secure-docker-images)</br>
&emsp;&emsp;[8.2. Bootstrap using node command, avoid npm start](#-82-bootstrap-using-node-command-avoid-npm-start)</br>
&emsp;&emsp;[8.3. Let the Docker runtime handle replication and uptime `#strategic`](#-83-let-the-docker-runtime-handle-replication-and-uptime)</br>
&emsp;&emsp;[8.4. Use .dockerignore to prevent leaking secrets](#-84-use-dockerignore-to-prevent-leaking-secrets)</br>
&emsp;&emsp;[8.5. Clean-up dependencies before production](#-85-clean-up-dependencies-before-production)</br>
&emsp;&emsp;[8.6. Shutdown smartly and gracefully `#advanced`](#-86-shutdown-smartly-and-gracefully)</br>
&emsp;&emsp;[8.7. Set memory limits using both Docker and v8 `#advanced` `#strategic`](#-87-set-memory-limits-using-both-docker-and-v8)</br>
&emsp;&emsp;[8.8. Plan for efficient caching](#-88-plan-for-efficient-caching)</br>
&emsp;&emsp;[8.9. Use explicit image reference, avoid latest tag](#-89-use-explicit-image-reference-avoid-latest-tag)</br>
&emsp;&emsp;[8.10. Prefer smaller Docker base images](#-810-prefer-smaller-docker-base-images)</br>
&emsp;&emsp;[8.11. Clean-out build-time secrets, avoid secrets in args `#strategic #new`](#-811-clean-out-build-time-secrets-avoid-secrets-in-args)</br>
&emsp;&emsp;[8.12. Scan images for multi layers of vulnerabilities `#advanced`](#-812-scan-images-for-multi-layers-of-vulnerabilities)</br>
&emsp;&emsp;[8.13 Clean NODE_MODULE cache](#-813-clean-node_module-cache)</br>
&emsp;&emsp;[8.14. Generic Docker practices](#-814-generic-docker-practices)</br>
&emsp;&emsp;[8.15. Lint your Dockerfile `#new`](#-815-lint-your-dockerfile)</br>

</details>

<br/><br/>

# `1. Project Architecture Practices`

## ![✔] 1.1 Structure your solution by business components

### `📝 #updated`

**TL;DR:** The root of a system should contain folders or repositories that represent reasonably sized business modules. Each component represents a product domain (i.e., bounded context), like 'user-component', 'order-component', etc. Each component has its own API, logic, and logical database. What is the significant merit? With an autonomous component, every change is performed over a granular and smaller scope - the mental overload, development friction, and deployment fear are much smaller and better. As a result, developers can move much faster. This does not necessarily demand physical separation and can be achieved using a Monorepo or with a multi-repo

```bash
my-system
├─ apps (components)
│  ├─ orders
│  ├─ users
│  ├─ payments
├─ libraries (generic cross-component functionality)
│  ├─ logger
│  ├─ authenticator
```

**Otherwise:** when artifacts from various modules/topics are mixed together, there are great chances of a tightly-coupled 'spaghetti' system. For example, in an architecture where 'module-a controller' might call 'module-b service', there are no clear modularity borders - every code change might affect anything else. With this approach, developers who code new features struggle to realize the scope and impact of their change. Consequently, they fear breaking other modules, and each deployment becomes slower and riskier

🔗 [**Read More: structure by components**](./sections/projectstructre/breakintcomponents.md)

<br/><br/>

## ![✔] 1.2 Layer your components with 3-tiers, keep the web layer within its boundaries

### `📝 #updated`

**TL;DR:** Each component should contain 'layers' - a dedicated folder for common concerns: 'entry-point' where controller lives, 'domain' where the logic lives, and 'data-access'. The primary principle of the most popular architectures is to separate the technical concerns (e.g., HTTP, DB, etc) from the pure logic of the app so a developer can code more features without worrying about infrastructural concerns. Putting each concern in a dedicated folder, also known as the [3-Tier pattern](https://en.wikipedia.org/wiki/Multitier_architecture), is the _simplest_ way to meet this goal

```bash
my-system
├─ apps (components)
│  ├─ component-a
   │  ├─ entry-points
   │  │
