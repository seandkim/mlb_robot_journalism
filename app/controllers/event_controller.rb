require 'nokogiri'
require 'open-uri'
require 'csv'

class EventController < ApplicationController
  ###############################
  ###### SELECT_DATE/GAME #######
  ###############################
  # takes in a list of directories in a single date
  # set dirgames_arr with list of game directories
  # and games_arr with a display version of dirgames_arr
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
  
  # takes in the name of the directory. 
  # returns a str for display to client
  # ex) gid_2016_07_10_atlmlb_chamlb_1/ => ATL vs CHA 
  def display(game_dir)
    str = game_dir[15,3].upcase << " vs " << game_dir[22,3].upcase
    return str
  end
    

  def select_date
  end

  def select_game
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
    texts_arr = games_html.xpath("//a/text()")

    filtergames(texts_arr)
  end
  
 
  ###############################
  ############ SHOW #############
  ###############################
  
  # takes in a xml doc that has list of players and their ids
  # returns a hash array where key=id, value=player name
  def players_xml2ids_hash(players_xml)
    players_arr = players_xml.css("player")
    ids_hash = Hash.new
    
    players_arr.each do |player| 
      id = player["id"]
      first = player["first"]
      last = player["last"]
      ids_hash[id] = last
    end
    return ids_hash
  end
  
  
  def lookup_pitcher(id) 
    player = @ids_hash[id]
    return player
  end
  
  def lookup_batter(id) 
    player = @ids_hash[id]
    return player
  end
  
  # csv를 array로 불르기
  def loadcsv(filename)
    #csv 파일 불러오기
    arr = []
    CSV.foreach(filename) do |row|
      arr << row
    end
    return arr
  end
  
  # takes in a bat event (hash table)
  # returns [ Win Expectancy of the bat event by looking up at winexp.cvs, 
  #           a string for debugging (either HOME/AWAY WIN or we_text) ]
  # set @team_won to "HOME" or "AWAY" once the game is over
  ### Win Expectancy 구하기
  def calc_we(bat_hash)
    #Score Differences(-15 ~ 15) 계산
    score_diff = (bat_hash["home_team_runs"].to_i) - (bat_hash["away_team_runs"].to_i)
    
    # if game is over (table lookup is not necessary)
    if bat_hash["inning"].to_i >= 9
      #away_team is winning
      if score_diff < 0
        if (bat_hash["half"] == "BOT" and bat_hash["o"] == "3")
          @team_won = "AWAY"
          return [0.0, "AWAY_WIN"]
        end
      #home_team is winning
      elsif score_diff > 0 
        # away team cannot attack anymore
        if (bat_hash["half"] == "BOT") or ((bat_hash["half"] == "TOP") and (bat_hash["o"]=="3"))
          @team_won = "HOME"
          return [100.0, "HOME_WIN"]
        end
      end
    end
    
    #조건1. Innings(1~9)
    # what if more than 12 inning?
    we_inning = bat_hash["inning"].to_s
    
    #조건2. Innings_status(1 or 2)
    if bat_hash["half"] == "TOP"
      we_inning_status = "1"
    else
      we_inning_status = "2"
    end
    
    #조건3. Basesit :: 1) none, 2) 1st, 3) 2nd, 4) 1st & 2nd, 5) 3rd, 6) 1st & 3rd, 7) 2nd & 3rd, 8) loaded
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
    
    #조건4. Outs(0~2)
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
        return [win_expectancy, we_text]
      end
    end
  end ### calc_we 메쏘드 닫기

  
  
  # takes in inning number, xml doc of a single inning, whether TOP or BOT
  # returns an array of "atbat"s with relevent information
  def bats_xml2bats_arr(i, bats_xml, half)
    #at_bat events in top/bottom of a single inning
    bats_arr = Array.new
    
    bats_xml.each do |bat_node|
      #bat_arr = [away_score, home_score, inningnum + top/bottom, 
      #           ball/strike/out count, pitcher, batter, event, description]
      
      #single at_bat event
      bat_hash = Hash.new
      bat_hash["away_team_runs"] = bat_node["away_team_runs"] 
      bat_hash["home_team_runs"] = bat_node["home_team_runs"] 
      bat_hash["inning"] = i.to_s
      bat_hash["half"] = half
      bat_hash["b"] = bat_node["b"]
      bat_hash["s"] = bat_node["s"]
      bat_hash["o"] = bat_node["o"]
      bat_hash["b1"] = bat_node["b1"]
      bat_hash["b2"] = bat_node["b2"]
      bat_hash["b3"] = bat_node["b3"]
      bat_hash["pitcher"] = lookup_pitcher(bat_node["pitcher"])
      bat_hash["batter"] = lookup_batter(bat_node["batter"])
      bat_hash["event"] = bat_node["event"]
      bat_hash["des"] = bat_node["des"]
      temp_arr = calc_we(bat_hash)
      bat_hash["WE"] = temp_arr[0]
      bat_hash["str"] = temp_arr[1]
      bat_hash["WPA"] = (bat_hash["WE"] - @prev_WE).round(1)
      @prev_WE = bat_hash["WE"]

      bats_arr << bat_hash
    end
    return bats_arr
  end
  
  
  # takes in xml file of a game 
  # returns game info in a nested array of the following structure:
  # [[inning_1], [inning_2] ... [inning_n]] 
  # where inning_i = [[top bat_1], [top bat_2]...[bottom bat_n]]
  # also set the best play from the team won as @bestBat
  def game_xml2game_table(game_xml)
    game_table = Array.new #array of bat_arr
    innings_arr = game_xml.css("inning")
    
    #for calculating WPA
    @prev_WE = 50.0
    
    (1..(innings_arr.length)).each do |i|
      inning = innings_arr[i-1]
      #top of a inning
      bats_str = inning.css("top")
      bats_xml = bats_str.css("atbat")
      bats_arr = bats_xml2bats_arr(i, bats_xml, "TOP")
      game_table << bats_arr

      #bottom of a inning
      bats_str = inning.css("bottom")
      bats_xml = bats_str.css("atbat")
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
      scalar = -1
    end
    
    bestBat = Hash.new
    bestWPA = -100.1
    
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
