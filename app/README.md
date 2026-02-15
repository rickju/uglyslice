用flutter做一个高尔夫app
----------------------------


Road Map
---------------------

第一阶段：静态地图

    flutter_map
    geolocator获取当前位置

第二阶段：数据层

    Overpass API or 本地GeoJSON: 球场info. Tee/reen坐标
    实现距离计算逻辑

    Added: load a local course list for quickly searching
    Added: show a round page when a course is selected
     todo: to play a round, select first: tee/color, 9holes/18holes, starting from 1 or 10, etc

    Add feature: get golf course info by calling overpass api. save as file for next time use.
    Add feature: show hole info: par3/4/5
    Add testing feature only in debug mode: set a pseudo user location for testing. e.g. set user location to tee when hole got switched

    Add feature in round page:
    set the map to show the current hole fairway, zoom accordingly, when hole is switched.
    When switching hole, move, zoom, and change view direction to show the hole fairway with whole screen 
    map view direction: facing the direction of the tee from current user location. e.g. the flag should on the top of the screen.
   rotate the map in this way: from the user or tee, the direction to flag is a vertical line to the screen top   


第三阶段: 交互功能

  Feature/记分卡/Scorecard: ListView/Table记录每洞杆数
  Feature/测距/Ruler： 允许用户在地图上点击任意一点，计算到该点的距离.....避开沙坑.

第四阶段: 优化

    离线地图: 使用 flutter_map_mbtiles 缓存地图数据，防止球场信号不好
    风向显示: 集成气象 API，显示实时风向和风速
    todo/feature: maintain a club set DB of all famous brands. so users can maintain clubs easily.


Android watch support
-----------------------
    Add feature: integrate android watch support: UI. switch hole button. 
    Add feature: integrate android watch support: UI. show current hole info: par3/4/5, distance to green.
    Add feature: integrate android watch support: use IMU to sense a swing.....


UI 
-----------

Add feature:  Bottom Nav Bar: 'Play', 'Scorecards', 'Settings'

         'Round page': play or review a round. show course/hole map
          'Play' Page: 1. select a golf course. 2. select tee 'white/black/red'.....   3. show 'Round' page
    'Scorecards' Page: show a list of history scores. when an item/round is clicked, show 'Round' page
      'Settings' Page: personal info: avatar/name/email/sex/age/handicap/home club, target handicap.



data structure:
------------------

User/Player:

    Course: name, gps location, scope/difficulty, meta data(holes)
    Hole: list of tee
    Tee: tee gps location, par count, handicap/difficult-rank
    Round: Course, tee, list of shot
    Shot: gps location, club

- 静态基础数据: 球场信息 ...
  动态活动数据: 单场比赛 ...

- clubInfo
    name, brand, number(7/8...), type(iron, wood,hybrid, ...), loft, 

- Course Info 球场: 描述球场的物理属性和基础信息
    id: 唯一标识符
    name: 球场名称
    location: 经纬度
    addr/地址: in text
    holes_count: 球洞总数 9/18

- Hole Info (球洞) -
    hole ID
    number: 第几洞（1-18）
    par: 标准杆数 3/4/5/... 
    handicap_index: 难度系数
    geometry: 地理围栏数据（果岭中心、中心线等，用于 GPS 计算）
    // course_id: 关联的球场ID

    * 9hole course: 1 hole, 2+ number
        e.g. hole ID -> tee white for #9, tee white for #18 ....
    * any chance: same fairway, 1 green for #9, another green for #18 ?
    * 重叠/overlap: 不同球洞互相重叠。 或者重用同一个fairway/green/tee

    * tee color VS tee prop:  pro/lady/senior

- Tee Info发球台:  同一球洞/难度/颜色/tee
    hole_id: 关联的球洞ID
    color: 黑、蓝、白、红....
    distance: 到果岭中心的距离,  distance to green front/back edge
    slope_rating / course_rating: 用于计算差点的专业参数

- Round Play 单场记录-  用户进行的一次比赛活动
    user_id: 运动员ID    多player支持?
    datetime
    total_score: 总杆数
    status: 进行中/已完成
    A list of holePlay

- holePlay:

    list of shotPlay of a hole in a round
    tee color: white/red/yellow/blue/black

- shotPlay/击球记录: 单场记录中最细颗粒度的数据
    round_id: 关联的比赛
    hole_id: 当前所在的球洞
    club: 使用的球杆, 7-Iron, Driver, ....
    start_location: 击球点GPS坐标
    end_location: 球落点GPS
    lie_type: 球位状态: 球道/长草/沙坑/果岭

    落点： OB/hazard/fairway/rough.  out of this hole/maybe neighour hole.

- relationship: holePlay/shotPlay VS moving breadcrumbs


- breadcrumbs: user moving route

    - flutter_background_geolocation - app后台轨迹采集(授权$399 )

    - 数据结构 {
            "t": 1707471200,   // Timestamp (Unix)
            "lat": 31.230412,  // 纬度
            "lng": 121.473734, // 经度
            "acc": 5,          // Accuracy (精度，单位：米)
            "spd": 1.2,        // Speed (米/秒)
            "alt": 15.2        // Altitude (海拔，用于分析球场坡度)
      }


    - local cache: real time data. no data loss with inet interrupt

    - cloud storage: route replay

            {
              "round_id": "GOLF-2026-001",
              "total_distance": 6500, // 总移动距离
              "path_data": "a~l~Fjk_uOee@vG...", // 压缩后的 Polyline 字符串
              "events": [
                {"type": "shot", "coord": [31.23, 121.47], "club": "7-Iron"},
                {"type": "rest", "duration": 300, "coord": [31.24, 121.48]}
              ]
            }

    - Compression: 
        使用 Google Polyline Algorithm 将点位数组压缩为字符串，可减少约 80% 的体积。

    - 地缘围栏 (Geofencing)：利用flutter_background_geolocation/addGeofence，自动识别进入发球台或离开果岭，触发球局进度切换。



Stat
---------------
.....处理数据...派生/Derived Data.....

 GIR (标准杆上果岭率)
 Fairway Hit (开球上球道): if 第一杆/Shot 1 landed_in Fairway
 FIR
 Putting: 单洞中 club == "Putter" 次数
 scrambling
 stroke gained


Bug List
------------------

fixed:  can NOT load holes info from karori_golf.json

