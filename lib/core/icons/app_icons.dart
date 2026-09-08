import 'package:flutter/cupertino.dart';

/// SF Symbols 风格图标。
/// 分类表只存字符串代码（[_categoryMap] 的 key），由这里集中映射为 IconData，
/// 数据层不依赖具体图标实现。
class FMIcons {
  const FMIcons._();

  static const IconData fallback = CupertinoIcons.tag_fill;

  /// 分类 iconCode → 图标。
  static IconData categoryIcon(String code) => _categoryMap[code] ?? fallback;

  /// 洞察卡片图标。
  static IconData insightIcon(String code) => switch (code) {
        'warning' => warning,
        'bell' => bell,
        'chart' => analysis,
        'trend_up' => CupertinoIcons.arrowtriangle_up_fill,
        'trend_down' => CupertinoIcons.arrowtriangle_down_fill,
        'repeat' => sync,
        _ => sparkles,
      };

  static const Map<String, IconData> _categoryMap = {
    // ---- 支出分类 ----
    'food': CupertinoIcons.flame_fill, // 餐饮（灶火）
    'transport': CupertinoIcons.bus, // 交通
    'shopping': CupertinoIcons.bag_fill, // 购物
    'housing': CupertinoIcons.house_fill, // 住房
    'entertainment': CupertinoIcons.film, // 娱乐
    'medical': CupertinoIcons.heart_fill, // 医疗
    'education': CupertinoIcons.book_fill, // 教育
    'travel': CupertinoIcons.airplane, // 旅行
    'pet': CupertinoIcons.paw_solid, // 宠物
    'telecom': CupertinoIcons.phone_fill, // 通讯
    'utilities': CupertinoIcons.bolt_fill, // 水电燃气
    'subscription': CupertinoIcons.repeat, // 订阅服务
    'insurance': CupertinoIcons.shield_fill, // 保险
    'car': CupertinoIcons.car_detailed, // 汽车
    'gift': CupertinoIcons.gift_fill, // 礼物
    'social': CupertinoIcons.person_2, // 人情
    'investment': CupertinoIcons.chart_bar_fill, // 投资
    'other': CupertinoIcons.ellipsis_circle, // 其他

    // ---- 收入分类 ----
    'salary': CupertinoIcons.money_yen_circle_fill, // 工资
    'bonus': CupertinoIcons.star_fill, // 奖金
    'parttime': CupertinoIcons.briefcase, // 兼职
    'invest_return': CupertinoIcons.graph_circle, // 投资收益
    'refund': CupertinoIcons.arrow_counterclockwise, // 退款
    'redpacket': CupertinoIcons.gift, // 红包
    'other_income': CupertinoIcons.ellipsis_circle, // 其他收入
  };

  // ---- 界面通用图标 ----
  static const IconData home = CupertinoIcons.home;
  static const IconData list = CupertinoIcons.list_bullet;
  static const IconData analysis = CupertinoIcons.chart_pie;
  static const IconData person = CupertinoIcons.person;
  static const IconData plus = CupertinoIcons.plus;
  static const IconData mic = CupertinoIcons.mic_fill;
  static const IconData camera = CupertinoIcons.camera_fill;
  static const IconData photo = CupertinoIcons.photo_fill;
  static const IconData keyboard = CupertinoIcons.square_pencil;
  static const IconData search = CupertinoIcons.search;
  static const IconData close = CupertinoIcons.xmark;
  static const IconData check = CupertinoIcons.checkmark;
  static const IconData checkCircle = CupertinoIcons.checkmark_circle_fill;
  static const IconData chevronLeft = CupertinoIcons.chevron_left;
  static const IconData chevronRight = CupertinoIcons.chevron_right;
  static const IconData chevronDown = CupertinoIcons.chevron_down;
  static const IconData trash = CupertinoIcons.trash_fill;
  static const IconData edit = CupertinoIcons.pencil;
  static const IconData calendar = CupertinoIcons.calendar;
  static const IconData clock = CupertinoIcons.clock_fill;
  static const IconData tag = CupertinoIcons.tag_fill;
  static const IconData store = CupertinoIcons.cart_fill;
  static const IconData card = CupertinoIcons.creditcard_fill;
  static const IconData note = CupertinoIcons.doc_text_fill;
  static const IconData invoice = CupertinoIcons.doc_text;
  static const IconData company = CupertinoIcons.briefcase;
  static const IconData sparkles = CupertinoIcons.sparkles;
  static const IconData waveform = CupertinoIcons.waveform;
  static const IconData warning = CupertinoIcons.exclamationmark_circle_fill;
  static const IconData info = CupertinoIcons.info_circle_fill;
  static const IconData shareUp = CupertinoIcons.share;
  static const IconData sync = CupertinoIcons.arrow_clockwise;
  static const IconData lock = CupertinoIcons.lock_fill;
  static const IconData logout = CupertinoIcons.square_arrow_right;
  static const IconData eye = CupertinoIcons.eye_fill;
  static const IconData eyeOff = CupertinoIcons.eye_slash;
  static const IconData bell = CupertinoIcons.bell_fill;
  static const IconData settings = CupertinoIcons.gear_alt;
  static const IconData globe = CupertinoIcons.globe;
  static const IconData location = CupertinoIcons.location_fill;
  static const IconData timer = CupertinoIcons.timer;
  static const IconData duplicate = CupertinoIcons.exclamationmark_circle_fill;
  static const IconData merge = CupertinoIcons.arrow_counterclockwise;
}
