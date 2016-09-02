require 'nokogiri'
require 'open-uri'
require 'csv'

# EventController
# takes care of 2 pages: select_game, show (select_date doesn't need functions)
# passes client's selections (date, game) between pages using parameter
class EventController < ApplicationController
  ########################################################################### 
  ############################### SELECT_GAME ###############################
  ## when a client chooses a date, lookup all the game hosted on that game ##
  ## and displays a list of those games for the client to choose           ##
  ###########################################################################
  
  # next two functions are helper functions used to create a list of games 
  # when the client choose a specific date
  
  # takes in a list of directories for a single date
  # filters only the game directories and set the list of them as @game_arr
  def filtergames(texts_arr) 
    @dirgames_arr = []
    @games_arr = []
    texts_arr.each do |text|
      text_str = text.to_s[1..-1]
      
      if text_str[0,4] == "gid_"
        @dirgames_arr << text_str
        @games_arr << display(text_str)
      end
    end
  end
  
  # takes in the name of the directory
  # returns a str for display to client
  # ex) gid_2016_07_10_atlmlb_chamlb_1/ => ATL vs CHA 
  def display(game_dir)
    str = game_dir[15,3].upcase << " vs " << game_dir[22,3].upcase
    return str
  end

  # takes in nothing, but uses values stored are params 
  # the params values (year,month,day) are set when client chooses a date
  def select_game
    # list of team names' code name & abbreviation
    @teamnames = loadcsv("teamnames.csv") 
    
    year = params["year"]
    month = params["month"]
    day = params["day"]

    # insert 0 if single digit
    if month.to_i < 10
      month.insert(0, "0")
    end
    if day.to_i < 10
      day.insert(0, "0")
    end
    
    @url = "http://www.mlb.com/gdcross/components/game/mlb/year_#{year}/month_#{month}/day_#{day}/"

    games_html = Nokogiri::XML(open(@url))
    texts_arr = games_html.xpath("//a/text()") #list of directories

    # filter out unnecessary (non-game) directories
    filtergames(texts_arr)
  end
  
  
  ########################################################################### 
  ################################## SHOW ###################################
  ## when client chooses a specific game, lists the play-by-play data and  ##
  ## its winning expectancy. Using the change in WE, selects the best play ##
  ###########################################################################
  
  # helper function for loading csv file into array
  # takes in file name
  # returns an array
  def loadcsv(filename)
    #csv 파일 불러오기
    arr = []
    CSV.foreach(filename) do |row|
      arr << row
    end
    return arr
  end
  
  # next two are helper functions for player name <=> their six digit number ID
  # takes in a xml doc that has a list of players and their ids
  # returns a hash array where key=id, value=player name
  def players_xml2ids_hash(players_xml)
    players_arr = players_xml.css("player")
    ids_hash = Hash.new
    
    players_arr.each do |player| 
      id = player["id"]
      #first = player["first"]
      last = player["last"]
      ids_hash[id] = last
    end
    return ids_hash
  end
  
  def lookup_player(id) 
    player = @ids_hash[id]
    return player
  end
  
  # takes in a bat event (which is a hash table)
  # returns Win Expectancy of the bat event by looking up at winexp.cvs
  # set @team_won to "HOME" or "AWAY" if the game is over
  # set @we_text as a string for debugging
  # most of the code is extracted from Dong-Hwan's code
  def calc_we(bat_hash)
    #Score Differences(-15 ~ 15) 계산
    score_diff = (bat_hash["home_team_runs"].to_i) - (bat_hash["away_team_runs"].to_i)
    
    # if game is over (table lookup is not necessary)
    if bat_hash["inning"].to_i >= 9
      # away_team is winning
      if score_diff < 0
        if (bat_hash["half"] == "BOT" and bat_hash["o"] == "3")
          @team_won = "AWAY"
          @we_text = "AWAY_WIN"
          return 0.0 #home team lost for sure
        end
      # home_team is winning
      elsif score_diff > 0 
        # away team cannot attack anymore
        if (bat_hash["half"] == "BOT") or ((bat_hash["half"] == "TOP") and (bat_hash["o"]=="3"))
          @team_won = "HOME"
          @we_text = "HOME_WIN"
          return 100.0 #home team won for sure
        end
      end
    end
    
    # need to generate four-digit for looking up in csv file
    # 조건1. Innings(1~9)
    we_inning = bat_hash["inning"].to_s
    
    # 조건2. Innings_status(1 or 2)
    if bat_hash["half"] == "TOP"
      we_inning_status = "1"
    else
      we_inning_status = "2"
    end
    
    # 조건3. Basesit :: 1) none, 2) 1st, 3) 2nd, 4) 1st & 2nd, 5) 3rd, 6) 1st & 3rd, 7) 2nd & 3rd, 8) loaded
    b1 = bat_hash["b1"]
    b2 = bat_hash["b2"]
    b3 = bat_hash["b3"]
    if (b1 == '') and (b2 == '') and (b3 == '')
      we_runners = "1"
    elsif (b1 != '') and (b2 == '') and (b3 == '')
      we_runners = "2"
    elsif (b1 == '') and (b2 != '') and (b3 == '')
      we_runners = "3"
    elsif (b1 != '') and (b2 != '') and (b3 == '')
      we_runners = "4"
    elsif (b1 == '') and (b2 == '') and (b3 != '')
      we_runners = "5"
    elsif (b1 != '') and (b2 == '') and (b3 != '')
      we_runners = "6"
    elsif (b1 == '') and (b2 != '') and (b3 != '')
      we_runners = "7"
    elsif (b1 != '') and (b2 != '') and (b3 != '')
      we_runners = "8"
    else
      we_runners = "9" #should not happen
    end
    
    # 조건4. Outs(0~2)
    we_out = bat_hash["o"]
    if bat_hash["o"] == "3"
      # deleted specific case ??
      # 3아웃이 되면 다음 공격팀에 맞춰 WE 조정하기 
      # (예, 1회초에 3아웃이 되면 1회말 시작에 맞게 승률을 높이고 1말 3아웃이 되면 2회초 승률로 고치기)
      if bat_hash["half"] == 'TOP'
        we_inning = bat_hash["inning"]
        we_inning_status = "2"
        we_runners = "1"
        we_out = "0"
      elsif bat_hash["half"] == 'BOT'
        we_inning = (bat_hash["inning"].to_i + 1).to_s
        we_inning_status = "1"
        we_runners = "1"
        we_out = "0"
      else 
        @error_flag = "조건4 ERROR"
      # doesn't cover all cases??
      end
    end
    
    #조건 1~4를 합쳐서 "InnBaseOut" 문자열 만들기 # why to_s??
    we_text = we_inning + we_inning_status + we_runners + we_out
    @we_text = we_text #for debugging
    
    #winexp.csv 테이블에서 스코어 차이에 따른 컬럼 위치 구하기.
    we_column = score_diff + 21
    # necessary??
    if score_diff < -20
      we_column = 0
    elsif score_diff > 20
      column = 40
    end
    
    #winexp.csv 테이블에서 컬럼에 담긴 값 빼오기.
    for j in 1 .. @winexp_arr.size-1
      if @winexp_arr[j][0] == we_text
        winexpcalc = @winexp_arr[j][we_column].to_f
        win_expectancy = (winexpcalc*100).round(1) #in percentage
        return win_expectancy
      end
    end
  end ### calc_we 메쏘드 닫기

  
  # takes in inning number, xml doc of a single inning, whether TOP or BOT
  # returns an array of "atbat"s with relevent information
  def bats_xml2bats_arr(inn, bats_xml, half)
    #at_bat events in top/bottom of a single inning
    bats_arr = Array.new
    
    (1..(bats_xml.length)).each do |i|
      bat_node = bats_xml[i-1]
    
      #bat_hash = [away_score, home_score, inningnum (as str), half (top/bottom) 
      #           ball/strike/out count, base situations, pitcher, batter, 
      #           event (type), description, WE, WPA]
      
      #single bat event (either atbat or action)
      bat_hash = Hash.new
      
      # distinguish atbat and action node
      # if action, use previous situation (because data are not recorded)
      if bat_node["pitcher"].to_i > 0
        bat_hash["type"] = "atbat"
      else
        bat_hash["type"] = "action"
      end
    
      bat_hash["away_team_runs"] = bat_node["away_team_runs"] 
      bat_hash["home_team_runs"] = bat_node["home_team_runs"] 
      bat_hash["inning"] = inn.to_s
      bat_hash["half"] = half
      bat_hash["event"] = bat_node["event"]
      bat_hash["des"] = bat_node["des"]
      
      if (bat_hash["type"] == "atbat") || (i==1) 
        bat_hash["b"] = bat_node["b"]
        bat_hash["s"] = bat_node["s"]
        bat_hash["o"] = bat_node["o"]
        bat_hash["b1"] = bat_node["b1"]
        bat_hash["b2"] = bat_node["b2"]
        bat_hash["b3"] = bat_node["b3"]
        bat_hash["pitcher"] = lookup_player(bat_node["pitcher"])
        bat_hash["batter"] = lookup_player(bat_node["batter"])
        
        bat_hash["WE"] = calc_we(bat_hash) #float
        bat_hash["str"] = @we_text
        bat_hash["WPA"] = (bat_hash["WE"] - @prev_bat["WE"]).round(1) #float
        @prev_bat = bat_hash
      
      #if action and first event of the inning (no previous bat event)
      elsif i==1  
        bat_hash["b"] = "0"
        bat_hash["s"] = "0"
        bat_hash["o"] = "0"
        bat_hash["b1"] = ""
        bat_hash["b2"] = ""
        bat_hash["b3"] = ""
        
      #if action, then copy previous bat event
      else #elsif bat_hash["type"] == "action" 
        bat_prev = bats_arr[i-2]
        bat_hash["b"] = bat_prev["b"]
        bat_hash["s"] = bat_prev["s"]
        bat_hash["o"] = bat_prev["o"]
        bat_hash["b1"] = bat_prev["b1"]
        bat_hash["b2"] = bat_prev["b2"]
        bat_hash["b3"] = bat_prev["b3"]
        bat_hash["pitcher"] = bat_prev["pitcher"]
        bat_hash["batter"] = bat_prev["pitcher"]
        
        bat_hash["str"] = "ACTION"
        
        #take care of stolen base, wild pitch, etc
        bat_hash = clean_action(bat_hash)
        
        bat_hash["WE"] = calc_we(bat_hash) #float
        bat_hash["WPA"] = (bat_hash["WE"] - @prev_bat["WE"]).round(1) #float
        @prev_bat = bat_hash
      end


      bats_arr << bat_hash
    end
    return bats_arr
  end
  
  # takes in bat hash
  # returns a bat hash with necessary change in base situation
  def clean_action(bat_hash)
    cleaned_bat_hash = bat_hash
    if bat_hash["event"][0,11] == "Stolen Base"
      if bat_hash["event"][12].to_i == 2
        cleaned_bat_hash["b2"] = bat_hash["b1"]
        cleaned_bat_hash["b1"] = ""
      elsif bat_hash["event"][12].to_i == 3
        cleaned_bat_hash["b3"] = bat_hash["b2"]
        cleaned_bat_hash["b2"] = ""
      #elsif bat_hash["event"][12].to_i == 4??
      end
    elsif bat_hash["event"] == "Wild Pitch" || bat_hash["event"] == "Passed Ball"
      #for debugging
      cleaned_bat_hash["str"] = bat_hash["event"]
      
      #clear out the bases
      cleaned_bat_hash["b1"] = ""
      cleaned_bat_hash["b2"] = ""
      cleaned_bat_hash["b3"] = ""
      
      #update base situation using description
      des = bat_hash["des"]
      if des.index("to 1st") != nil
        cleaned_bat_hash["b1"] = "1" #change to player name
      end
      if des.index("to 2nd") != nil
        cleaned_bat_hash["b2"] = "1" #change to player name
      end
      if des.index("to 3rd") != nil
        cleaned_bat_hash["b3"] = "1" #change to player name
      end
    end
    return cleaned_bat_hash
  end
  
  # takes in xml file of a game 
  # returns game info in a nested array of the following structure:
  # [[inning_1], [inning_2] ... [inning_n]] 
  # where inning_i = [[top bat_1], [top bat_2]...[bottom bat_n]]
  # also set the best play from the team won as @bestBat
  def game_xml2game_table(game_xml)
    game_table = Array.new #array of bat_arr
    innings_xml_arr = game_xml.css("inning")
    
    #for calculating WPA
    @prev_bat = Hash.new
    @prev_bat["WE"] = 50.0 #equal probability at first
    
    (1..(innings_xml_arr.length)).each do |i|
      inning = innings_xml_arr[i-1]
      #top of a inning
      bats_str = inning.css("top")
      
      #keeps the order of atbat and action
      bats_xml = bats_str.search('atbat, action')
      bats_xml.map(&:to_xml)
      
      bats_arr = bats_xml2bats_arr(i, bats_xml, "TOP")
      game_table << bats_arr

      #bottom of a inning
      bats_str = inning.css("bottom")
      
      #keeps the order of atbat and action
      bats_xml = bats_str.search('atbat, action')
      bats_xml.map(&:to_xml)
      
      bats_arr = bats_xml2bats_arr(i, bats_xml, "BOT")
      game_table << bats_arr
    end 
    
    @bestBat = bestBat(game_table)
    
    
    return game_table
  end


  # takes in a game_table
  # return the best bat event from winning team by highest |WPA|
  def bestBat(game_table)
    #for getting best WPA from the team won
    if @team_won == "HOME"
      scalar = 1
    else
      scalar = -1 #get the most negative WPA
    end
    
    bestBat = Hash.new
    bestWPA = -100.1 #lower than lowest WPA
    
    game_table.each do |inning|
      inning.each do |bat_hash|
        bat_WPA = bat_hash["WPA"]
        if (bat_WPA * scalar) > bestWPA 
          bestBat = bat_hash
          bestWPA = bat_WPA
        end
      end
    end
    
    return bestBat
  end

  def show
    url = params["url"]
    @str = url
    
    # inefficient! Please use database
    # example url: http://www.mlb.com/gdcross/components/game/mlb/year_2016/month_07/day_10/gid_2016_07_10_anamlb_balmlb_1/ 
    @home_team_code = url[95, 3]
    @away_team_code = url[88, 3]
    @game_year = url[52, 4]
    @game_month= url[63, 2]
    @game_day = url[70, 2]

    # for identifying player id
    players_url = url + "players.xml"
    @str1 = players_url
    players_xml = Nokogiri::XML(open(players_url))
    @ids_hash = players_xml2ids_hash(players_xml)

    # list of events
    game_url = url + "game_events.xml"
    game_xml = Nokogiri::XML(open(game_url))
    @winexp_arr = loadcsv("winexp.csv")
    @game_table = game_xml2game_table(game_xml)
  end
end
