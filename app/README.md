用flutter做一个高尔夫app
----------------------------


Road Map
---------------------

第一阶段：静态地图

    集成 flutter_map
    通过 geolocator 获取当前位置

第二阶段：数据层

    使用 Overpass API 或本地 GeoJSON 文件定义球场的发球台（Tee）和果岭（Green）坐标
    实现距离计算逻辑

    Add feature: show hole info: par3/4/5
    Add testing feature only in debug mode: set a pseudo user location for testing. e.g. set user location to tee when hole got switched
    Add feature: set the map to show the current hole fairway, zoom accordingly, when hole is switched.
                 When switching hole, move, zoom, and change view direction to show the hole fairway with whole screen 
                 map view direction: facing the direction of the tee from current user location. e.g. the flag should on the top of the screen.
                rotate the map in this way: from the user or tee, the direction to flag is a vertical line to the screen top   

    Add feature: get golf course info by calling overpass api. save as file for next time use.
    

第三阶段：交互功能

    记分卡Scorecard:使  用 ListView 或 Table 组件记录每洞杆数
    测距/Ruler： 允许用户在地图上点击任意一点，计算到该点的距离.....避开沙坑...


第四阶段：优化

    离线地图：使用 flutter_map_mbtiles 缓存地图数据，防止球场信号不好
    风向显示：集成气象 API，显示实时风向和风速


Android watch support
-----------------------
    Add feature: integrate android watch support: UI. switch hole button. 
    Add feature: integrate android watch support: UI. show current hole info: par3/4/5, distance to green.
    Add feature: integrate android watch support: use IMU to sense a swing.....

UI 
-----------

Add feature: 'Round page': play or review a round 
Add feature:  Bottom Nav Bar: 'Play', 'Scorecards', 'Settings'

          'Play' Page: 1. select a golf course. 2. select tee 'white/black/red'.....   3. show course map tee #1
    'Scorecards' Page: show a list of history scores. click an item. show the course map tee #1
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
    location: 经纬度或地址
    holes_count: 球洞总数（通常为 9 或 18）

- Hole Info (球洞) -  每个球场包含多个球洞
    course_id: 关联的球场 ID
    number: 第几洞（1-18）
    par: 标准杆数
    handicap_index: 难度系数
    geometry: 地理围栏数据（果岭中心、中心线等，用于 GPS 计算）

- Tee Info发球台:  同一球洞根据难度/颜色不同的发球点
    hole_id: 关联的球洞 ID
    color: 发球台颜色（黑、蓝、白、红等)
    distance: 到果岭中心的距离,  distance to green front/back edge
    slope_rating / course_rating: 用于计算差点的专业参数

- Round Play 单场记录-  用户进行的一次比赛活动
    user_id: 运动员 ID
    course_id: 所在的球场
    date: 比赛日期
    total_score: 总杆数
    status: 进行中 / 已完成
    list of holePlay

- holePlay:

     list of shots of a hole in a round

- Shot (击球记录) 单场记录中最细颗粒度的数据
    round_id: 关联的比赛
    hole_id: 当前所在的球洞
    club: 使用的球杆, 7-Iron, Driver, ....
    start_location: 击球点GPS坐标
    end_location: 球落点GPS
    lie_type: 球位状态（球道、长草、沙坑、果岭）


Stat
---------------
.....处理这些数据，派生/Derived Data.....

 GIR (标准杆上果岭率)
 Fairway Hit (开球上球道): if 第一杆/Shot 1 landed_in Fairway
 Putting: 单洞中 club == "Putter" 次数


Bug List
------------------

fixed:  can NOT load holes info from karori_golf.json

