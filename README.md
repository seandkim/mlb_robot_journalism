#MLB Robot Jounralism 

##About
This is a program that fetches play-by-play data of a game from MLB.com 
and analyzes the overall trend of the game. Using the analysis, it detects 
the highlights of the game and generates a short article (in Korean) on the game chosen.

##Authors
- Written by Sean D Kim from Carnegie Mellon University 
- Under the guidance of Professor Joon-Hwan Lee and Dong-Hwan Kim from Seoul National University

##Language/Module
- Ruby on Rails
- Nokogiri for parsing xml file

##Data Source
- All the game data from MLB.com
- WE (Win Expectany) and WPA (Win Percentage Added) is calcuated using table 
    provided by fangraphs.com (?) This table can be found in winexp.csv

##Files
- teamnames.csv: contains abbreviation and the code name of each team
- winexp.csv: contains WE of a specific situation of a baseball game

##Method
The program consist of three main parts. 
1. Data scraping
  - All the MLB game data are organized at <http://www.mlb.com/gdcross/components/game/mlb/>
  - To find a specfic game data, navigate through directories in the following order. 
    - year => month => day => game (starts with gid_...)
  - Once specific data is found, the following info can be found in the following folders 
    - players.xml: list of player name and their 6 digit number ID (this number 
       ID is used in the game data)
    - game_events.xml: every event in the game is recorded here. 

2. Data Analysis 
  - From game_events.xml: 
    - At every <atbat> element, the following data was recorded from the following attributes
        - Away team score from attribute "away_team_runs"
        - Home team score from attribute "home_team_runs"
        - Current Inning from the parent element, <inning>
        - Ball count from attribute "b"
        - Strike count from attribute "s"
        - Out count from attribute "o"
        - Player present in the first base from attribute "b1"
        - Player present in the second base from attribute "b2"
        - Player present in the third base from attribute "b3"
        - Current pitcher from attribute "pitcher"
        - Current batter from attribute "batter"
        - Type of event from attribute "event" (ex. flyout, single)
        - Description of the event from attribute "des"
    - At every <action> element, update the necessary situation change using adequate attributes. 
        - Stolen Base: Attribute "event" indicates which base was stolen. (ex. event="Stolen Base 2b")
            Update the base situation accordingly.         
        - Wild Pitch: Attribute "des" identifies the base situation changes. Change accordingly. 
        - Game Advisory, Manager Review, Pitching Substitution, Offensive Sub, 
            Defensive Sub: Do nothing. 
        - Pickoff Error 1B: (Yet Implemented)
  - Additionally, WE (Win Expectany) and WPA (Win Percentage Added) was calculated using winexp.csv
    - calculate column and row value
      - column: (away team points) – (home team points)
      - row: four digit number generated in the following way
        - 1st digit: Current inning
        - 2nd digit: 1 if Top (away team on offense), 2 if Bottom (home team on offense)
        - 3rd digit: if the player(s) are at the following base(s)...
          - none => 1
          - first base => 2
          - second base=> 3
          - first & second base => 4
          - third base=> 5
          - first & third base => 6
          - second & third base => 7
          - all bases => 8
        - 4th digit: number of outs
    - the WE is the number found at the column and row calculated above
    - WPA is calculated by subtracting previous WE from the current WE
    - WE is closer to 1 if home team is more likely to win, closer to 0 if away team is more likely to win

3. Generating Article
  - The highlights of the game is identified by highest change in WE (greatest |WPA|)
  - The sentence is generated using algorithm developed by the research team of Professor Joon-Hwan Lee from Seoul National University

##Shortcomings
The followings are the shortcomings that needs to be fixed. 
- <action> elements 
    - not all events are being taken care of
        - Pickoff: base situation update necessary
        - Substitution: change the player
        - Search for more events that could happen in a <action> element
    - when the first element is <action>, the pitcher/batter is empty
- Database
    - Current implementation does not make usage of database. Loading players and 
        storing game data can be done more effectively using database.  