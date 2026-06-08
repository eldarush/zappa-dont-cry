# Project Based Learning

[![Gitter](https://badges.gitter.im/practical-tutorials/community.svg)](https://gitter.im/practical-tutorials/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)

A list of programming tutorials in which aspiring software developers learn how to build an application from scratch. These tutorials are divided into different primary programming languages. Tutorials may involve multiple technologies and languages.

To get started, simply fork this repo. Please refer to [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

## Table of Contents:

- [C#](#c)
- [C/C++](#cc)
- [Clojure](#clojure)
- [Dart](#dart)
- [Elixir](#elixir)
- [Erlang](#erlang)
- [F#](#f)
- [Go](#go)
- [Haskell](#haskell)
- [HTML/CSS](#html-and-css)
- [Java](#java)
- [JavaScript](#javascript)
- [Kotlin](#kotlin)
- [Lua](#lua)
- [OCaml](#ocaml)
- [PHP](#php)
- [Python](#python)
- [R](#r)
- [Ruby](#ruby)
- [Rust](#rust)
- [Scala](#scala)
- [Swift](#swift)
- [Additional resources](#additional-resources)

## C/C++:

- [Build an Interpreter](http://www.craftinginterpreters.com/) (Chapter 14 on is written in C)
- [Memory Allocators 101 - Write a simple memory allocator](https://arjunsreedharan.org/post/148675821737/memory-allocators-101-write-a-simple-memory)
- [Write a Shell in C](https://brennan.io/2015/01/16/write-a-shell-in-c/)
- [Write a FUSE Filesystem](https://www.cs.nmsu.edu/~pfeiffer/fuse-tutorial/)
- [Build Your Own Text Editor](http://viewsourcecode.org/snaptoken/kilo/)
- [Build Your Own Lisp](http://www.buildyourownlisp.com/)
- [How to Program an NES Game in C](https://nesdoug.com/)
- [Write an OS from scratch](https://github.com/tuhdo/os01)
- [How to create an OS from scratch ](https://github.com/cfenollosa/os-tutorial)
- [Building a CHIP-8 Emulator](https://austinmorlan.com/posts/chip8_emulator/)
- [Beginning Game Programming with C++ and SDL](http://lazyfoo.net/tutorials/SDL/)
- [Implementing a Key-Value Store](http://codecapsule.com/2012/11/07/ikvs-implementing-a-key-value-store-table-of-contents/)
- Tiny 3D graphics projects
  - [Tiny Renderer or how OpenGL works: software rendering in 500 lines of code](https://github.com/ssloy/tinyrenderer/wiki)
  - [Understandable RayTracing in 256 lines of bare C++](https://github.com/ssloy/tinyraytracer/wiki)
  - [KABOOM! in 180 lines of bare C++](https://github.com/ssloy/tinykaboom/wiki)
  - [486 lines of C++: old-school FPS in a weekend](https://github.com/ssloy/tinyraycaster/wiki)
- Writing a minimal x86-64 JIT compiler in C++
  - [Part 1](https://solarianprogrammer.com/2018/01/10/writing-minimal-x86-64-jit-compiler-cpp/)
  - [Part 2](https://solarianprogrammer.com/2018/01/12/writing-minimal-x86-64-jit-compiler-cpp-part-2/)
- [Build a Live Code-reloader Library for C++](http://howistart.org/posts/cpp/1/index.html)
- [Write a hash table in C](https://github.com/jamesroutley/write-a-hash-table)
- [Let's Build a Simple Database](https://cstack.github.io/db_tutorial/)
- [Let's Write a Kernel](http://arjunsreedharan.org/post/82710718100/kernel-101-lets-write-a-kernel)
- [Write a Bootloader in C](http://3zanders.co.uk/2017/10/13/writing-a-bootloader/)
- [Linux Container in 500 Lines of Code](https://blog.lizzie.io/linux-containers-in-500-loc.html)
- [Write Your Own Virtual Machine](https://justinmeiners.github.io/lc3-vm/)
- [Learning KVM - Implement Your Own Linux Kernel](https://david942j.blogspot.com/2018/10/note-learning-kvm-implement-your-own.html)
- [Build Your Own Redis with C/C++](https://build-your-own.org/redis/)
- Write a C compiler
  - [Part 1: Integers, Lexing and Code Generation](https://norasandler.com/2017/11/29/Write-a-Compiler.html)
  - [Part 2: Unary Operators](https://norasandler.com/2017/12/05/Write-a-Compiler-2.html)
  - [Part 3: Binary Operators](https://norasandler.com/2017/12/15/Write-a-Compiler-3.html)
  - [Part 4: Even More Binary Operators](https://norasandler.com/2017/12/28/Write-a-Compiler-4.html)
  - [Part 5: Local Variables](https://norasandler.com/2018/01/08/Write-a-Compiler-5.html)
  - [Part 6: Conditionals](https://norasandler.com/2018/02/25/Write-a-Compiler-6.html)
  - [Part 7: Compound Statements](https://norasandler.com/2018/03/14/Write-a-Compiler-7.html)
  - [Part 8: Loops](https://norasandler.com/2018/04/10/Write-a-Compiler-8.html)
  - [Part 9: Functions](https://norasandler.com/2018/06/27/Write-a-Compiler-9.html)
  - [Part 10: Global Variables](https://norasandler.com/2019/02/18/Write-a-Compiler-10.html)
- [Implementing a Language with LLVM](https://llvm.org/docs/tutorial/#kaleidoscope-implementing-a-language-with-llvm)
- [Meta Crush Saga: a C++17 compile-time game](https://jguegant.github.io//jguegant.github.io/blogs/tech/meta-crush-saga.html)
- [High-Performance Matrix Multiplication](https://gist.github.com/nadavrot/5b35d44e8ba3dd718e595e40184d03f0)
- Space Invaders from Scratch
  - [Part 1](http://nicktasios.nl/posts/space-invaders-from-scratch-part-1.html)
  - [Part 2](http://nicktasios.nl/posts/space-invaders-from-scratch-part-2.html)
  - [Part 3](http://nicktasios.nl/posts/space-invaders-from-scratch-part-3.html)
  - [Part 4](http://nicktasios.nl/posts/space-invaders-from-scratch-part-4.html)
  - [Part 5](http://nicktasios.nl/posts/space-invaders-from-scratch-part-5.html)
- [Tetris Tutorial in C++ Platform Independent](http://javilop.com/gamedev/tetris-tutorial-in-c-platform-independent-focused-in-game-logic-for-beginners/)
- Writing a Linux Debugger
  - [Part 1: Setup](https://blog.tartanllama.xyz/writing-a-linux-debugger-setup/)
  - [Part 2: Breakpoints](https://blog.tartanllama.xyz/writing-a-linux-debugger-breakpoints/)
  - [Part 3: Registers and memory](https://blog.tartanllama.xyz/writing-a-linux-debugger-registers/)
  - [Part 4: Elves and dwarves](https://blog.tartanllama.xyz/writing-a-linux-debugger-elf-dwarf/)
  - [Part 5: Source and signals](https://blog.tartanllama.xyz/writing-a-linux-debugger-source-signal/)
  - [Part 6: Source-level stepping](https://blog.tartanllama.xyz/writing-a-linux-debugger-dwarf-step/)
  - [Part 7: Source-level breakpoints](https://blog.tartanllama.xyz/writing-a-linux-debugger-source-break/)
  - [Part 8: Stack unwinding](https://blog.tartanllama.xyz/writing-a-linux-debugger-unwinding/)
  - [Part 9: Handling variables](https://blog.tartanllama.xyz/writing-a-linux-debugger-variables/)
  - [Part 10: Advanced topics](https://blog.tartanllama.xyz/writing-a-linux-debugger-advanced-topics/)
- Let's write a compiler
  - [Part 1: Introduction, selecting a language, and doing some planning](https://briancallahan.net/blog/20210814.html)
  - [Part 2: A lexer](https://briancallahan.net/blog/20210815.html)
  - [Part 3: A parser](https://briancallahan.net/blog/20210816.html)
  - [Part 4: Testing](https://briancallahan.net/blog/20210817.html)
  - [Part 5: A code generator](https://briancallahan.net/blog/20210818.html)
  - [Part 6: Input and output](https://briancallahan.net/blog/20210819.html)
  - [Part 7: Arrays](https://briancallahan.net/blog/20210822.html)
  - [Part 8: Strings, forward references, and conclusion](https://briancallahan.net/blog/20210826.html)

### Network programming

- Let's Code a TCP/IP Stack

  - [Part 1: Ethernet & ARP](http://www.saminiir.com/lets-code-tcp-ip-stack-1-ethernet-arp/)
  - [Part 2: IPv4 & ICMPv4](http://www.saminiir.com/lets-code-tcp-ip-stack-2-ipv4-icmpv4/)
  - [Part 3: TCP Basics & Handshake](http://www.saminiir.com/lets-code-tcp-ip-stack-3-tcp-handshake/)
  - [Part 4: TCP Data Flow & Socket API](http://www.saminiir.com/lets-code-tcp-ip-stack-4-tcp-data-flow-socket-api/)
  - [Part 5: TCP Retransmission](http://www.saminiir.com/lets-code-tcp-ip-stack-5-tcp-retransmission/)

- Programming concurrent servers

  - [Part 1 - Introduction](https://eli.thegreenplace.net/2017/concurrent-servers-part-1-introduction/)
  - [Part 2 - Threads](https://eli.thegreenplace.net/2017/concurrent-servers-part-2-threads/)
  - [Part 3 - Event-driven](https://eli.thegreenplace.net/2017/concurrent-servers-part-3-event-driven/)
  - [Part 4 - libuv](https://eli.thegreenplace.net/2017/concurrent-servers-part-4-libuv/)
  - [Part 5 - Redis case study](https://eli.thegreenplace.net/2017/concurrent-servers-part-5-redis-case-study/)
  - [Part 6 - Callbacks, Promises and async/await](https://eli.thegreenplace.net/2018/concurrent-servers-part-6-callbacks-promises-and-asyncawait/)

- MQTT Broker from scratch
  - [Part 1 - The protocol](https://codepr.github.io/posts/sol-mqtt-broker)
  - [Part 2 - Networking](https://codepr.github.io/posts/sol-mqtt-broker-p2)
  - [Part 3 - Server](https://codepr.github.io/posts/sol-mqtt-broker-p3)
  - [Part 4 - Data structures](https://codepr.github.io/posts/sol-mqtt-broker-p4)
  - [Part 5 - Topic abstraction](https://codepr.github.io/posts/sol-mqtt-broker-p5)
  - [Part 6 - Handlers](https://codepr.github.io/posts/sol-mqtt-broker-p6)
  - [Bonus - Multithreading](https://codepr.github.io/posts/sol-mqtt-broker-bonus)

### OpenGL:

- Creating 2D Breakout game clone in C++ with OpenGL
  - [Breakout](https://learnopengl.com/In-Practice/2D-Game/Breakout)
  - [Setting up](https://learnopengl.com/In-Practice/2D-Game/Setting-up)
  - [Rendering Sprites](https://learnopengl.com/In-Practice/2D-Game/Rendering-Sprites)
  - [Levels](https://learnopengl.com/In-Practice/2D-Game/Levels)
  - Collisions
    - [Ball](https://learnopengl.com/In-Practice/2D-Game/Collisions/Ball)
    - [Collision detection](https://learnopengl.com/In-Practice/2D-Game/Collisions/Collision-detection)
    - [Collision resolution](https://learnopengl.com/In-Practice/2D-Game/Collisions/Collision-resolution)
  - [Particles](https://learnopengl.com/In-Practice/2D-Game/Particles)
  - [Postprocessing](https://learnopengl.com/In-Practice/2D-Game/Postprocessing)
  - [Powerups](https://learnopengl.com/In-Practice/2D-Game/Powerups)
  - [Audio](https://learnopengl.com/In-Practice/2D-Game/Audio)
  - [Render text](https://learnopengl.com/In-Practice/2D-Game/Render-text)
  - [Final thoughts](https://learnopengl.com/In-Practice/2D-Game/Final-thoughts)
- [Handmade Hero](https://handmadehero.org)
- [How to Make Minecraft in C++/OpenGL](https://www.youtube.com/playlist?list=PLMZ_9w2XRxiZq1vfw1lrpCMRDufe2MKV_) (video)

## C#:

- [Learn C# By Building a Simple RPG Game](http://scottlilly.com/learn-c-by-building-a-simple-rpg-index/)
- [Create a Rogue-like game in C#](https://roguesharp.wordpress.com/)
- [Create a Blank App with C# and Xamarin (work in progress)](https://www.intertech.com/Blog/xamarin-tutorial-part-1-create-a-blank-app/)
- [Build iOS Photo Library App with Xamarin and Visual Studio](https://www.raywenderlich.com/134049/building-ios-apps-with-xamarin-and-visual-studio)
- [Building the CoreWiki](https://www.youtube.com/playlist?list=PLVMqA0_8O85yC78I4Xj7z48ES48IQBa7p) This is a Wiki-style content management system that has been completely written in C# with ASP.NET Core and Razor Pages. You can find the source code [here](https://github.com/csharpfritz/CoreWiki).

## Clojure:

- [Build a Twitter Bot with Clojure](http://howistart.org/posts/clojure/1/index.html)
- [Building a Spell-Checker](https://bernhardwenzel.com/articles/clojure-spellchecker/)
- [Building a JIRA integration with Clojure & Atlassian Connect](https://hackernoon.com/building-a-jira-integration-with-clojure-atlassian-connect-506ebd112807)
- [Prototyping with Clojure](https://github.com/aliaksandr-s/prototyping-with-clojure)
- [Tetris in ClojureScript](https://shaunlebron.github.io/t3tr0s-slides)

## Dart:

### Flutter:

- [Amazon Clone with Admin Panel](https://youtu.be/O3nmP-lZAdg)
- [Food Delivery App](https://youtu.be/7dAt-JMSCVQ)
- [Google Docs Clone](https://youtu.be/0_GJ1w_iG44)
- [Instagram Clone](https://youtu.be/mEPm9w5QlJM)
- [Multiplayer TicTacToe Game](https://youtu.be/Aut-wfXacXg)
- [TikTok Clone](https://youtu.be/4E4V9F3cbp4)
- [Ticket Booking App](https://youtu.be/71AsYo2q_0Y)
- [Travel App](https://youtu.be/x4DydJKVvQk)
- [Twitch Clone](https://youtu.be/U9YKZrDX0CQ)
- [WhatsApp Clone](https://youtu.be/yqwfP2vXWJQ)
- [Wordle Clone](https://youtu.be/_W0RN_Cqhpg)
- [Zoom Clone](https://youtu.be/sMA1dKbv33Y)
- [Netflix Clone](https://youtu.be/J8IFNKzs3TI)

## Elixir

- [Building a Simple Chat App With Elixir and Phoenix](https://sheharyar.me/blog/simple-chat-phoenix-elixir/)
- [How to write a super fast link shortener with Elixir, Phoenix, and Mnesia](https://medium.com/free-code-camp/how-to-write-a-super-fast-link-shortener-with-elixir-phoenix-and-mnesia-70ffa1564b3c)

## Erlang

- [ChatBus : build your first multi-user chat room app with Erlang/OTP](https://medium.com/@kansi/chatbus-build-your-first-multi-user-chat-room-app-with-erlang-otp-b55f72064901)
- [Making a Chat App with Erlang, Rebar, Cowboy and Bullet](http://marianoguerra.org/posts/making-a-chat-app-with-erlang-rebar-cowboy-and-bullet.html)

## F#:

- [Write your own Excel in 100 lines of F#](http://tomasp.net/blog/2018/write-your-own-excel)

## Java:

- [Build an Interpreter](http://www.craftinginterpreters.com/) (Chapter 4-13 is written in Java)
- [Build a Simple HTTP Server with Java](http://javarevisited.blogspot.com/2015/06/how-to-create-http-server-in-java-serversocket-example.html)
- [Build an Android Flashlight App](https://www.youtube.com/watch?v=dhWL4DC7Krs) (video)
- [Build a Spring Boot App with User Authentication](https://spring.io/guides/gs/securing-web/)

## JavaScript:

- [Build 30 things in 30 days with 30 tutorials](https://javascript30.com)
- [Build an App in Pure JS](https://medium.com/codingthesmartway-com-blog/pure-javascript-building-a-real-world-application-from-scratch-5213591cfcd6)
- [Build a Jupyter Notebook Extension](https://link.medium.com/wWUO7TN8SS)
- [Build a TicTacToe Game with JavaScript](https://medium.com/javascript-in-plain-english/build-tic-tac-toe-game-using-javascript-3afba3c8fdcc)
- [Build a Simple Weather App With Vanilla JavaScript](https://webdesign.tutsplus.com/tutorials/build-a-simple-weather-app-with-vanilla-javascript--cms-33893)
- [Build a Todo List App in JavaScript](https://github.com/dwyl/javascript-todo-list-tutorial)

## HTML and CSS:

- [Build A Loading Screen](https://medium.freecodecamp.org/how-to-build-a-delightful-loading-screen-in-5-minutes-847991da509f)
- [Build an HTML Calculator with JS](https://medium.freecodecamp.org/how-to-build-an-html-calculator-app-from-scratch-using-javascript-4454b8714b98)
- [Build Snake using only JavaScript, HTML & CSS](https://www.freecodecamp.org/news/think-like-a-programmer-how-to-build-snake-using-only-javascript-html-and-css-7b1479c3339e/)

### Mobile Application:

- [Build a React Native Todo Application](https://egghead.io/courses/build-a-react-native-todo-application)
- [Build a React Native Application with Redux Thunk](https://medium.com/@alialhaddad/how-to-use-redux-thunk-in-react-and-react-native-4743a1321bd0)

### Web Applications:

#### React:

- [Create Serverless React.js Apps](http://serverless-stack.com/)
- [Create a Trello Clone](http://codeloveandboards.com/blog/2016/01/04/trello-tribute-with-phoenix-and-react-pt-1/)
- [Create a Character Voting App with React, Node, MongoDB and SocketIO](http://sahatyalkabov.com/create-a-character-voting-app-using-react-nodejs-mongodb-and-socketio)
- [React Tutorial: Cloning Yelp](https://www.fullstackreact.com/articles/react-tutorial-cloning-yelp/)
- [Build a Full Stack Movie Voting App with Test-First Development using Mocha, React, Redux and Immutable](https://teropa.info/blog/2015/09/10/full-stack-redux-tutorial.html)
- [Build a Twitter Stream with React and Node](https://scotch.io/tutorials/build-a-real-time-twitter-stream-with-node-and-react-js)
- [Build A Simple Medium Clone using React.js and Node.js](https://medium.com/@kris101/clone-medium-on-node-js-and-react-js-731cdfbb6878)
- [Integrate MailChimp in JS](https://medium.freecodecamp.org/how-to-integrate-mailchimp-in-a-javascript-web-app-2a889fb43f6f)
- [Build A Chrome Extension with React + Parcel](https://medium.freecodecamp.org/building-chrome-extensions-in-react-parcel-79d0240dd58f)
- [Build A ToDo App With React Native](https://blog.hasura.io/tutorial-fullstack-react-native-with-graphql-and-authentication-18183d13373a)
- [Make a Chat Application](https://medium.freecodecamp.org/how-to-build-a-chat-application-using-react-redux-redux-saga-and-web-sockets-47423e4bc21a)
- [Create a News App with React Native](https://medium.freecodecamp.org/create-a-news-app-using-react-native-ced249263627)
- [Learn Webpack For React](https://medium.freecodecamp.org/learn-webpack-for-react-a36d4cac5060)
- [Testing React App With Puppeteer and Jest](https://blog.bitsrc.io/testing-your-react-app-with-puppeteer-and-jest-c72b3dfcde59)
- [Build Your Own React Boilerplate](https://medium.freecodecamp.org/how-to-build-your-own-react-boilerplate-2f8cbbeb9b3f)
- [Code The Game Of Life With React](https://medium.freecodecamp.org/create-gameoflife-with-react-in-one-hour-8e686a410174)
- [A Basic React+Redux Introductory Tutorial](https://hackernoon.com/a-basic-react-redux-introductory-tutorial-adcc681eeb5e)
- [Build an Appointment Scheduler](https://hackernoon.com/build-an-appointment-scheduler-using-react-twilio-and-cosmic-js-95377f6d1040)
- [Build A Chat App with Sentiment Analysis](https://codeburst.io/build-a-chat-app-with-sentiment-analysis-using-next-js-c43ebf3ea643)
- [Build A Full Stack Web Application Setup](https://hackernoon.com/full-stack-web-application-using-react-node-js-express-and-webpack-97dbd5b9d708)
- [Create Todoist clone with React and Firebase](https://www.youtube.com/watch?v=hT3j87FMR6M)
- Build A Random Quote Machine
  - [Part 1](https://www.youtube.com/watch?v=3QngsWA9IEE)
  - [Part 2](https://www.youtube.com/watch?v=XnoTmO06OYo)
  - [Part 3](https://www.youtube.com/watch?v=us51Jne67_I)
  - [Part 4](https://www.youtube.com/watch?v=iZx7hqHb5MU)
  - [Part 5](https://www.youtube.com/watch?v=lpba9vBqXl0)
  - [Part 6](https://www.youtube.com/watch?v=Jvp8j6zrFHE)
  - [Part 7](https://www.youtube.com/watch?v=M_hFfrN8_PQ)
- [React Phone E-Commerce Project(video)](https://www.youtube.com/watch?v=-edmQKcOW8s)

#### Angular:

- [Build an Instagram Clone with Angular 1.x](https://hackhands.com/building-instagram-clone-angularjs-satellizer-nodejs-mongodb/)
- Build an offline-capable Hacker News client with Angular 2+
  - [Part 1](https://houssein.me/angular2-hacker-news)
  - [Part 2](https://houssein.me/progressive-angular-applications)
- [Build a Google+ clone with Django and AngularJS (Angular 1.x)](https://thinkster.io/django-angularjs-tutorial)
- Build A Beautiful Real World App with Angular 8 :

  - [Part I](https://medium.com/@hamedbaatour/build-a-real-world-beautiful-web-app-with-angular-6-a-to-z-ultimate-guide-2018-part-i-e121dd1d55e)
  - [Part II](https://medium.com/@hamedbaatour/build-a-real-world-beautiful-web-app-with-angular-8-the-ultimate-guide-2019-part-ii-fe70852b2d6d)

- [Build Responsive layout with BootStrap 4 and Angular 6](https://medium.com/@tomastrajan/how-to-build-responsive-layouts-with-bootstrap-4-and-angular-6-cfbb108d797b)
- ToDo App with Angular 5
  - [Introduction to Angular](http://www.discoversdk.com/blog/intro-to-angular-and-the-evolution-of-the-web)
  - [Part 1](http://www.discoversdk.com/blog/angular-5-to-do-list-app-part-1)

#### Node:

- [Build a real-time Markdown Editor with NodeJS](https://scotch.io/tutorials/building-a-real-time-markdown-viewer)
- [Test-Driven Development with Node, Postgres and Knex](http://mherman.org/blog/2016/04/28/test-driven-development-with-node/)
- Write a Twitter Bot in Node.js
  - [Part 1](https://codeburst.io/build-a-simple-twitter-bot-with-node-js-in-just-38-lines-of-code-ed92db9eb078)
  - [Part 2](https://codeburst.i
