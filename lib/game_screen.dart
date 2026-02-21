import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;

class GameScreen extends StatefulWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late GameState gameState;
  late Timer gameTimer;
  late FocusNode focusNode;
  bool prevSpacePressed = false;
  bool leftPressed = false;
  bool rightPressed = false;

  @override
  void initState() {
    super.initState();
    focusNode = FocusNode();
    gameState = GameState();
    gameTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      // Автоматическая стрельба раз в 0.5 секунды
      if ((DateTime.now().millisecond ~/ 50) % 10 == 0) {
        gameState.shoot();
      }

      // Пробел - проверяем напрямую через HardwareKeyboard
      if (HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.space)) {
        gameState.shoot();
      }

      // Проверяем стрелки через RawKeyboard напрямую
      final leftArrowPressed = HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.arrowLeft);
      final rightArrowPressed = HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.arrowRight);

      if (rightArrowPressed && !leftArrowPressed) {
        gameState.player.moveRight();
      } else if (leftArrowPressed && !rightArrowPressed) {
        gameState.player.moveLeft();
      }

      setState(() {
        gameState.update();
      });
    });
  }

  @override
  void dispose() {
    gameTimer.cancel();
    focusNode.dispose();
    super.dispose();
  }

  void _restartGame() {
    gameTimer.cancel();
    setState(() {
      gameState = GameState();
    });
    gameTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      // Автоматическая стрельба раз в 0.5 секунды
      if ((DateTime.now().millisecond ~/ 50) % 10 == 0) {
        gameState.shoot();
      }

      // Проверяем стрелки через RawKeyboard напрямую
      final leftArrowPressed = HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.arrowLeft);
      final rightArrowPressed = HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.arrowRight);

      if (rightArrowPressed && !leftArrowPressed) {
        gameState.player.moveRight();
      } else if (leftArrowPressed && !rightArrowPressed) {
        gameState.player.moveLeft();
      }

      setState(() {
        gameState.update();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onHorizontalDragUpdate: (details) {
          gameState.player.x += details.delta.dx;
          gameState.player.x = gameState.player.x.clamp(30, gameState.screenSize.width - 30);
        },
        onTap: () {
          // Если игра закончилась и нажал на кнопку Try Again
          if (gameState.gameOver) {
            final tapPos = GestureDetector(onTap: () {}).toString();
            // Проверяем если нажали в области кнопки
            // Используем простой способ - просто перезапускаем на любой тап
            _restartGame();
          } else {
            gameState.shoot();
          }
        },
        child: CustomPaint(
          painter: GamePainter(gameState, _restartGame),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class GameState {
  late Player player;
  List<Enemy> enemies = [];
  List<Bullet> bullets = [];
  List<Bonus> bonuses = [];
  List<Particle> particles = [];
  List<Star> stars = [];

  int score = 0;
  int level = 1;
  int lastLevelBonus = 0; // Отслеживаем последний уровень с бонусом
  int health = 100;
  bool gameOver = false;
  double lastDamage = -1; // Для эффекта пульса при урона

  double enemySpawnRate = 2.0;
  double lastEnemySpawn = 0;

  late Size screenSize;
  final math.Random random = math.Random();

  GameState() {
    screenSize = const Size(400, 800);
    player = Player(screenSize.width / 2, screenSize.height - 50);
    _initStars();
  }

  void _initStars() {
    // Звёзды по всему экрану - включая правый край
    final width = screenSize.width;
    final height = screenSize.height;

    for (int i = 0; i < 200; i++) {
      stars.add(Star(
        random.nextDouble() * width,
        random.nextDouble() * height,
      ));
    }
  }

  void shoot() {
    if (player.lastShot < player.fireRate) return;
    bullets.add(Bullet(player.x, player.y - 20));
    player.lastShot = 0;
  }

  void update() {
    if (gameOver) return;

    player.update();

    lastEnemySpawn += 0.03;
    if (lastEnemySpawn > (1.0 / enemySpawnRate)) {
      _spawnEnemy();
      lastEnemySpawn = 0;
    }

    for (var enemy in enemies) {
      enemy.update();
    }
    for (var bullet in bullets) {
      bullet.update();
    }
    for (var bonus in bonuses) {
      bonus.update(this);
    }
    for (var star in stars) {
      star.update(screenSize.height, screenSize.width);
    }
    for (var particle in particles) {
      particle.update();
    }

    enemies.removeWhere((e) => e.y > screenSize.height);
    bullets.removeWhere((b) => b.y < 0);
    bonuses.removeWhere((b) => b.y > screenSize.height);
    particles.removeWhere((p) => p.life <= 0);

    for (var bullet in bullets.toList()) {
      for (var enemy in enemies.toList()) {
        if (_checkCollision(bullet, enemy)) {
          bullets.remove(bullet);
          _createExplosion(enemy.x + 15, enemy.y + 15);
          if (enemy.takeDamage(1)) {
            score += (10 + level * 5);

            // Разные эффекты при убийстве врагов
            if (enemy.type == EnemyType.asteroid) {
              // Серая пыль для камней
              _createDust(enemy.x + 15, enemy.y + 15, const Color(0xFFCCCCCC), 15);
            } else if (enemy.type == EnemyType.alien) {
              // Зелёный крестик для обычных тварей
              _createCross(enemy.x + 15, enemy.y + 15, const Color(0xFF00FF00));
              // Бонус падает редко - 10% шанс
              if (random.nextDouble() < 0.1) {
                bonuses.add(Bonus(enemy.x, enemy.y));
              }
            } else if (enemy.type == EnemyType.bigAlien) {
              // Жёлтый треугольник для большой твари
              _createTriangle(enemy.x + 30, enemy.y + 30, const Color(0xFFFFFF00));
              // Бонус падает редко - 15% шанс для большой твари
              if (random.nextDouble() < 0.15) {
                bonuses.add(Bonus(enemy.x, enemy.y));
              }
            }

            enemies.remove(enemy);
          }
          break;
        }
      }
    }

    for (var bonus in bonuses.toList()) {
      if (_checkCollisionRect(player, bonus)) {
        // Если аптечка - добавляем 10 здоровья
        if (bonus.type == 'medkit') {
          health = math.min(100, health + 10);
        } else {
          bonus.apply(this);
        }
        bonuses.remove(bonus);
      }
    }

    for (var enemy in enemies.toList()) {
      if (_checkCollisionRect(player, enemy)) {
        // Разный урон для разных врагов
        int damage = 0;
        if (enemy.type == EnemyType.asteroid) {
          damage = 10;
        } else if (enemy.type == EnemyType.alien) {
          damage = 20;
        } else if (enemy.type == EnemyType.bigAlien) {
          damage = 40;
        }

        health -= damage;
        lastDamage = 0;
        _createExplosion(player.x, player.y);
        enemies.remove(enemy);
        if (health <= 0) {
          gameOver = true;
        }
      }
    }

    if (score > level * 1000) {
      level++;
      enemySpawnRate += 0.3;

      // За каждый новый уровень даём бонус - выбираем случайный из 2
      if (level > lastLevelBonus) {
        lastLevelBonus = level;
        final bonusType = random.nextBool() ? 'medkit' : 'purple_bullets';
        final bonus = Bonus(screenSize.width / 2, 0)..type = bonusType;
        bonuses.add(bonus);
      }
    }
  }

  void _createExplosion(double x, double y) {
    for (int i = 0; i < 8; i++) {
      final angle = (2 * math.pi * i) / 8;
      particles.add(Particle(
        x,
        y,
        math.cos(angle) * 150,
        math.sin(angle) * 150,
      ));
    }
  }

  void _createDust(double x, double y, Color color, int count) {
    // Облако пыли при убийстве камня - круги разного размера
    for (int i = 0; i < count * 3; i++) {
      final angle = math.Random().nextDouble() * 2 * math.pi;
      final speed = 100 + math.Random().nextDouble() * 200;
      final size = 1.0 + math.Random().nextDouble() * 4.0; // Разные размеры 1-5
      particles.add(Particle(
        x,
        y,
        math.cos(angle) * speed,
        math.sin(angle) * speed,
      )..dustSize = size);
    }
  }

  void _createCross(double x, double y, Color color) {
    // Статический крестик - появляется и исчезает
    particles.add(Particle(x, y, 0, 0)..color = color);
  }

  void _createTriangle(double x, double y, Color color) {
    // Жёлтый треугольник - специальная частица
    for (int i = 0; i < 3; i++) {
      particles.add(Particle(x, y, 0, 0)..color = color);
    }
  }

  void _spawnEnemy() {
    final type = random.nextInt(100);
    late EnemyType enemyType;

    // 1% шанс на большую тварь
    if (type == 0) {
      enemyType = EnemyType.bigAlien;
    } else if (type < 60) {
      enemyType = EnemyType.asteroid;
    } else {
      enemyType = EnemyType.alien;
    }

    final x = random.nextDouble() * screenSize.width;
    enemies.add(Enemy(x, -40, enemyType, level));
  }

  bool _checkCollision(Bullet bullet, Enemy enemy) {
    return bullet.x < enemy.x + 50 &&
        bullet.x + 8 > enemy.x &&
        bullet.y < enemy.y + 50 &&
        bullet.y + 24 > enemy.y;
  }

  bool _checkCollisionRect(dynamic a, dynamic b) {
    return a.x < b.x + 40 &&
        a.x + 40 > b.x &&
        a.y < b.y + 40 &&
        a.y + 40 > b.y;
  }
}

class Player {
  double x;
  double y;
  double fireRate = 0.15;
  double lastShot = 0.15;
  double bulletSize = 1.0;
  Color bulletColor = const Color(0xFF00FFFF);

  Player(this.x, this.y);

  void update() {
    lastShot += 0.03;
    // Используем доступную ширину экрана вместо жёстких значений
    x = x.clamp(30, 800 - 30); // Увеличил до 800 для браузера
  }

  void moveLeft() {
    x -= 12;
  }

  void moveRight() {
    x += 12;
  }
}

class Enemy {
  double x;
  double y;
  int health = 1;
  int maxHealth = 1;
  EnemyType type;
  double speed = 50;
  double velocityX = 0;
  double lastDamageTaken = -1;
  double zigzagTime = 0; // Для зигзага движения

  Enemy(this.x, this.y, this.type, int level) {
    switch (type) {
      case EnemyType.asteroid:
        health = 2;
        maxHealth = 2;
        speed = 3600 + (level * 200);
        velocityX = (math.Random().nextDouble() - 0.5) * speed * 0.5;
        break;
      case EnemyType.comet:
        health = 1;
        maxHealth = 1;
        speed = 4500 + (level * 250);
        break;
      case EnemyType.alien:
        health = 2;
        maxHealth = 2;
        speed = 2700 + (level * 150);
        break;
      case EnemyType.bigAlien:
        health = 5; // 5 попаданий для большой твари
        maxHealth = 5;
        speed = 2000 + (level * 100);
        break;
    }
  }

  void update() {
    y += speed * 0.03 / 100;
    x += velocityX * 0.03 / 100;

    // Зигзаг для тварей
    if (type == EnemyType.alien || type == EnemyType.bigAlien) {
      zigzagTime += 0.03;
      x += math.sin(zigzagTime * 3) * 2; // Лёгкий зигзаг
    }
  }

  bool takeDamage(int amount) {
    health -= amount;
    lastDamageTaken = 0;
    return health <= 0;
  }
}

class Bullet {
  double x;
  double y;
  double speed = 10800;

  Bullet(this.x, this.y);

  void update() {
    y -= speed * 0.03 / 100;
  }
}

class Bonus {
  double x;
  double y;
  late String type;
  double speed = 200;
  late GameState game; // Для движения к корабль

  Bonus(this.x, this.y) {
    final random = math.Random();
    final types = ['medkit', 'purple_bullets'];
    // 60% - аптечка, 20% - фиолетовые пули
    final rand = random.nextDouble();
    if (rand < 0.6) {
      type = 'medkit';
    } else {
      type = 'purple_bullets';
    }
  }

  void update(GameState gameState) {
    // Падают вниз очень медленно
    y += speed / 100;

    // Сразу двигаются к кораблю по прямой линии
    final dx = gameState.player.x - x;
    final dy = gameState.player.y - y;
    final distance = math.sqrt(dx * dx + dy * dy);

    if (distance > 5) {
      // Нормализуем и движемся к корабль со скоростью 80
      x += (dx / distance) * 80 * 0.03 / 100;
      y += (dy / distance) * 80 * 0.03 / 100;
    }
  }

  void apply(GameState game) {
    switch (type) {
      case 'fast_shot':
        game.player.fireRate = (game.player.fireRate * 0.5).clamp(0.01, game.player.fireRate);
        break;
      case 'thick_bullet':
        game.player.bulletSize = 1.5;
        Future.delayed(const Duration(seconds: 5), () {
          game.player.bulletSize = 1.0;
        });
        break;
      case 'health':
        game.health = 100;
        break;
      case 'medkit':
      // Аптечка даёт 10 здоровья
        game.health = math.min(100, game.health + 10);
        break;
      case 'purple_bullets':
      // Фиолетовые пули - увеличиваем скорость и размер
        game.player.bulletSize = 2.0;
        game.player.fireRate = (game.player.fireRate * 0.3).clamp(0.01, game.player.fireRate);
        game.player.bulletColor = const Color(0xFF7700FF);
        Future.delayed(const Duration(seconds: 10), () {
          game.player.bulletSize = 1.0;
          game.player.bulletColor = const Color(0xFF00FFFF);
        });
        break;
    }
  }
}

class Particle {
  double x;
  double y;
  double vx;
  double vy;
  int life = 30;
  Color? color; // Для специальных эффектов
  double dustSize = 2.0; // Размер пыли

  Particle(this.x, this.y, this.vx, this.vy);

  void update() {
    x += vx * 0.03 / 100;
    y += vy * 0.03 / 100;
    life--;
  }
}

class Star {
  double x;
  double y;
  double opacity;

  Star(this.x, this.y) : opacity = 0.3 + math.Random().nextDouble() * 0.7;

  void update(double screenHeight, double screenWidth) {
    y += 30 * 0.03 / 100;
    // Также они медленно скользят влево и переходят справа на влево
    x -= 50 * 0.03 / 100;

    if (y > screenHeight) {
      y = 0;
    }
    if (x < 0) {
      x = screenWidth;
    }
    if (x > screenWidth) {
      x = 0;
    }
  }
}

enum EnemyType { asteroid, comet, alien, bigAlien }

class GamePainter extends CustomPainter {
  final GameState gameState;
  final VoidCallback? onRestartPressed;

  GamePainter(this.gameState, [this.onRestartPressed]);

  @override
  void paint(Canvas canvas, Size size) {
    gameState.screenSize = size;

    // Градиент фона - сине-фиолетовый
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0a0e27),
    );

    // Звёзды
    for (var star in gameState.stars) {
      canvas.drawCircle(
        Offset(star.x, star.y),
        1,
        Paint()..color = Color.fromARGB((255 * star.opacity).toInt(), 100, 200, 255),
      );
    }

    // Сетка
    final gridPaint = Paint()
      ..color = const Color(0xFF1a2f5a)
      ..strokeWidth = 0.5;
    for (double i = 0; i < size.width; i += 50) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    }
    for (double i = 0; i < size.height; i += 50) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);
    }

    _drawPlayer(canvas, gameState.player);

    // Пульсирующий красный круг при урона
    if (gameState.lastDamage >= 0 && gameState.lastDamage < 0.4) {
      final pulseRadius = 50 + (math.sin(gameState.lastDamage * 15.7) * 10);
      canvas.drawCircle(
        Offset(gameState.player.x, gameState.player.y + 15),
        pulseRadius,
        Paint()
          ..color = const Color(0xFFFF0000).withOpacity(0.5)
          ..style = PaintingStyle.fill,
      );
      gameState.lastDamage += 0.016;
    }

    for (var enemy in gameState.enemies) {
      _drawEnemy(canvas, enemy);
    }

    for (var bullet in gameState.bullets) {
      // Гладкая пуля - закругленная форма
      final paint = Paint()..color = gameState.player.bulletColor;
      // Острый конец спереди
      canvas.drawCircle(
        Offset(bullet.x, bullet.y - 3 * gameState.player.bulletSize),
        2 * gameState.player.bulletSize,
        paint,
      );
      // Тупой конец сзади
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bullet.x - 2 * gameState.player.bulletSize, bullet.y + 2 * gameState.player.bulletSize, 4 * gameState.player.bulletSize, 3 * gameState.player.bulletSize),
          Radius.circular(2 * gameState.player.bulletSize),
        ),
        paint,
      );
      // Гладкий корпус
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bullet.x - 2.5 * gameState.player.bulletSize, bullet.y - 1 * gameState.player.bulletSize, 5 * gameState.player.bulletSize, 8 * gameState.player.bulletSize),
          Radius.circular(1.5 * gameState.player.bulletSize),
        ),
        paint,
      );
    }

    for (var bonus in gameState.bonuses) {
      _drawBonus(canvas, bonus);
    }

    // Частицы взрыва и эффекты
    for (var particle in gameState.particles) {
      if (particle.color != null) {
        // Крутящиеся решётки 3x3 при убийстве любого врага
        final angle = (DateTime.now().millisecond / 100) * 2 * math.pi;
        canvas.save();
        canvas.translate(particle.x, particle.y);
        canvas.rotate(angle);

        final paint = Paint()
          ..color = particle.color!.withOpacity(particle.life / 30)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;

        // Решётка 3x3 с точками
        for (int i = -1; i <= 1; i++) {
          for (int j = -1; j <= 1; j++) {
            canvas.drawCircle(
              Offset(i * 4.0, j * 4.0),
              1.5,
              paint,
            );
          }
        }

        // Горизонтальные линии
        canvas.drawLine(
          const Offset(-6, -4),
          const Offset(6, -4),
          paint,
        );
        canvas.drawLine(
          const Offset(-6, 0),
          const Offset(6, 0),
          paint,
        );
        canvas.drawLine(
          const Offset(-6, 4),
          const Offset(6, 4),
          paint,
        );

        // Вертикальные линии
        canvas.drawLine(
          const Offset(-4, -6),
          const Offset(-4, 6),
          paint,
        );
        canvas.drawLine(
          const Offset(0, -6),
          const Offset(0, 6),
          paint,
        );
        canvas.drawLine(
          const Offset(4, -6),
          const Offset(4, 6),
          paint,
        );

        canvas.restore();
      } else {
        // Обычные частицы пыли - серого цвета, разные размеры
        canvas.drawCircle(
          Offset(particle.x, particle.y),
          particle.dustSize,
          Paint()
            ..color = Color.fromARGB(
              (255 * particle.life / 30).toInt(),
              200,
              200,
              200,
            ),
        );
      }
    }

    _drawHUD(canvas, size);

    if (gameState.gameOver) {
      _drawGameOver(canvas, size);
    }
  }

  void _drawPlayer(Canvas canvas, Player player) {
    const cellSize = 6.0;

    final paintPurple = Paint()..color = const Color(0xFF7700FF);
    final paintCyan = Paint()..color = const Color(0xFF00FFFF);
    final paintBlue = Paint()..color = const Color(0xFF0088FF);

    // Нос (острый)
    _drawPixel(canvas, player.x - 3, player.y - 18, cellSize, paintCyan);
    _drawPixel(canvas, player.x, player.y - 18, cellSize, paintCyan);
    _drawPixel(canvas, player.x + 3, player.y - 18, cellSize, paintCyan);

    // Верхний обвес
    _drawPixel(canvas, player.x - 6, player.y - 12, cellSize, paintPurple);
    _drawPixel(canvas, player.x - 3, player.y - 12, cellSize, paintCyan);
    _drawPixel(canvas, player.x, player.y - 12, cellSize, paintCyan);
    _drawPixel(canvas, player.x + 3, player.y - 12, cellSize, paintCyan);
    _drawPixel(canvas, player.x + 6, player.y - 12, cellSize, paintPurple);

    // Верхняя часть корпуса
    _drawPixel(canvas, player.x - 9, player.y - 6, cellSize, paintPurple);
    _drawPixel(canvas, player.x - 6, player.y - 6, cellSize, paintCyan);
    _drawPixel(canvas, player.x - 3, player.y - 6, cellSize, paintBlue);
    _drawPixel(canvas, player.x, player.y - 6, cellSize, paintBlue);
    _drawPixel(canvas, player.x + 3, player.y - 6, cellSize, paintBlue);
    _drawPixel(canvas, player.x + 6, player.y - 6, cellSize, paintCyan);
    _drawPixel(canvas, player.x + 9, player.y - 6, cellSize, paintPurple);

    // Большие крылья сбоку
    _drawPixel(canvas, player.x - 15, player.y, cellSize, paintPurple);
    _drawPixel(canvas, player.x - 12, player.y, cellSize, paintPurple);
    _drawPixel(canvas, player.x - 9, player.y, cellSize, paintCyan);

    _drawPixel(canvas, player.x + 9, player.y, cellSize, paintCyan);
    _drawPixel(canvas, player.x + 12, player.y, cellSize, paintPurple);
    _drawPixel(canvas, player.x + 15, player.y, cellSize, paintPurple);

    // Нижняя часть корпуса
    _drawPixel(canvas, player.x - 9, player.y + 6, cellSize, paintPurple);
    _drawPixel(canvas, player.x - 6, player.y + 6, cellSize, paintCyan);
    _drawPixel(canvas, player.x - 3, player.y + 6, cellSize, paintBlue);
    _drawPixel(canvas, player.x, player.y + 6, cellSize, paintBlue);
    _drawPixel(canvas, player.x + 3, player.y + 6, cellSize, paintBlue);
    _drawPixel(canvas, player.x + 6, player.y + 6, cellSize, paintCyan);
    _drawPixel(canvas, player.x + 9, player.y + 6, cellSize, paintPurple);

    // Двигатели (короче чем было)
    final engineFrame = (DateTime.now().millisecond ~/ 80) % 3;
    if (engineFrame > 0) {
      final enginePaint = Paint()..color = const Color(0xFFFFFF00);
      _drawPixel(canvas, player.x - 3, player.y + 12, cellSize, enginePaint);
      _drawPixel(canvas, player.x, player.y + 12, cellSize, enginePaint);
      _drawPixel(canvas, player.x + 3, player.y + 12, cellSize, enginePaint);

      if (engineFrame == 2) {
        _drawPixel(canvas, player.x - 1, player.y + 18, cellSize, enginePaint);
        _drawPixel(canvas, player.x + 1, player.y + 18, cellSize, enginePaint);
      }
    }
  }

  void _drawPixel(Canvas canvas, double x, double y, double size, Paint paint) {
    canvas.drawRect(Rect.fromLTWH(x, y, size, size), paint);
  }

  void _drawEnemy(Canvas canvas, Enemy enemy) {
    const cellSize = 4.0;
    final paintRed = Paint()..color = const Color(0xFFFF3333);
    final paintOrange = Paint()..color = const Color(0xFFFF8800);

    switch (enemy.type) {
      case EnemyType.asteroid:
      // Лунный камень - серый с кратерами (в 3 раза больше)
        const craterCellSize = 6.0;
        final paintGray = Paint()..color = const Color(0xFFCCCCCC);
        final paintDarkGray = Paint()..color = const Color(0xFF666666);
        final paintCrater = Paint()..color = const Color(0xFF444444);

        // Основной контур камня
        _drawPixel(canvas, enemy.x + 15, enemy.y + 0, craterCellSize, paintGray);
        _drawPixel(canvas, enemy.x + 21, enemy.y + 0, craterCellSize, paintGray);

        _drawPixel(canvas, enemy.x + 9, enemy.y + 6, craterCellSize, paintGray);
        _drawPixel(canvas, enemy.x + 15, enemy.y + 6, craterCellSize, paintGray);
        _drawPixel(canvas, enemy.x + 21, enemy.y + 6, craterCellSize, paintGray);
        _drawPixel(canvas, enemy.x + 27, enemy.y + 6, craterCellSize, paintGray);

        _drawPixel(canvas, enemy.x + 3, enemy.y + 12, craterCellSize, paintGray);
        _drawPixel(canvas, enemy.x + 9, enemy.y + 12, craterCellSize, paintGray);
        _drawPixel(canvas, enemy.x + 15, enemy.y + 12, craterCellSize, paintGray);
        _drawPixel(canvas, enemy.x + 21, enemy.y + 12, craterCellSize, paintGray);
        _drawPixel(canvas, enemy.x + 27, enemy.y + 12, craterCellSize, paintGray);
        _drawPixel(canvas, enemy.x + 33, enemy.y + 12, craterCellSize, paintGray);

        _drawPixel(canvas, enemy.x + 9, enemy.y + 18, craterCellSize, paintGray);
        _drawPixel(canvas, enemy.x + 15, enemy.y + 18, craterCellSize, paintGray);
        _drawPixel(canvas, enemy.x + 21, enemy.y + 18, craterCellSize, paintGray);
        _drawPixel(canvas, enemy.x + 27, enemy.y + 18, craterCellSize, paintGray);

        _drawPixel(canvas, enemy.x + 15, enemy.y + 24, craterCellSize, paintGray);
        _drawPixel(canvas, enemy.x + 21, enemy.y + 24, craterCellSize, paintGray);

        // Кратеры (тёмные пятна)
        _drawPixel(canvas, enemy.x + 15, enemy.y + 6, craterCellSize, paintCrater);
        _drawPixel(canvas, enemy.x + 21, enemy.y + 12, craterCellSize, paintCrater);
        _drawPixel(canvas, enemy.x + 9, enemy.y + 12, craterCellSize, paintDarkGray);
        _drawPixel(canvas, enemy.x + 27, enemy.y + 18, craterCellSize, paintDarkGray);
        break;

      case EnemyType.comet:
      // Космическая комета - яркая красно-оранжевая звезда (увеличено в 2 раза)
        _drawPixel(canvas, enemy.x + 28, enemy.y + 10, cellSize, paintRed);

        _drawPixel(canvas, enemy.x + 24, enemy.y + 14, cellSize, paintOrange);
        _drawPixel(canvas, enemy.x + 28, enemy.y + 14, cellSize, paintRed);
        _drawPixel(canvas, enemy.x + 32, enemy.y + 14, cellSize, paintOrange);

        _drawPixel(canvas, enemy.x + 20, enemy.y + 18, cellSize, paintOrange);
        _drawPixel(canvas, enemy.x + 24, enemy.y + 18, cellSize, paintRed);
        _drawPixel(canvas, enemy.x + 28, enemy.y + 18, cellSize, paintRed);
        _drawPixel(canvas, enemy.x + 32, enemy.y + 18, cellSize, paintRed);
        _drawPixel(canvas, enemy.x + 36, enemy.y + 18, cellSize, paintOrange);

        _drawPixel(canvas, enemy.x + 24, enemy.y + 22, cellSize, paintOrange);
        _drawPixel(canvas, enemy.x + 28, enemy.y + 22, cellSize, paintRed);
        _drawPixel(canvas, enemy.x + 32, enemy.y + 22, cellSize, paintOrange);

        // Хвост кометы
        _drawPixel(canvas, enemy.x + 28, enemy.y + 26, cellSize, paintRed);
        _drawPixel(canvas, enemy.x + 28, enemy.y + 30, cellSize, paintOrange);
        _drawPixel(canvas, enemy.x + 28, enemy.y + 34, cellSize, paintOrange);
        break;

      case EnemyType.alien:
      // Осьминог - ЗЕЛЁНЫЙ с красными глазами и щупальцами
        const cellSize = 4.0;
        final paintGreen = Paint()..color = const Color(0xFF00FF00);
        final paintRed = Paint()..color = const Color(0xFFFF3333);

        // Полупрозрачный красный круг при попадании
        if (enemy.lastDamageTaken >= 0 && enemy.lastDamageTaken < 0.3) {
          canvas.drawCircle(
            Offset(enemy.x + 30, enemy.y + 20),
            45,
            Paint()
              ..color = const Color(0xFFFF0000).withOpacity(0.4)
              ..style = PaintingStyle.fill,
          );
          enemy.lastDamageTaken += 0.03;
        }

        // Голова (центр)
        _drawPixel(canvas, enemy.x + 24, enemy.y + 8, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 28, enemy.y + 8, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 32, enemy.y + 8, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 36, enemy.y + 8, cellSize, paintGreen);

        _drawPixel(canvas, enemy.x + 20, enemy.y + 12, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 24, enemy.y + 12, cellSize, paintRed); // Глаз
        _drawPixel(canvas, enemy.x + 28, enemy.y + 12, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 32, enemy.y + 12, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 36, enemy.y + 12, cellSize, paintRed); // Глаз
        _drawPixel(canvas, enemy.x + 40, enemy.y + 12, cellSize, paintGreen);

        _drawPixel(canvas, enemy.x + 24, enemy.y + 16, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 28, enemy.y + 16, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 32, enemy.y + 16, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 36, enemy.y + 16, cellSize, paintGreen);

        // Щупальца (8 штук вниз)
        _drawPixel(canvas, enemy.x + 16, enemy.y + 20, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 20, enemy.y + 20, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 24, enemy.y + 20, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 28, enemy.y + 20, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 32, enemy.y + 20, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 36, enemy.y + 20, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 40, enemy.y + 20, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 44, enemy.y + 20, cellSize, paintGreen);

        // Концы щупалец
        _drawPixel(canvas, enemy.x + 16, enemy.y + 24, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 20, enemy.y + 24, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 40, enemy.y + 24, cellSize, paintGreen);
        _drawPixel(canvas, enemy.x + 44, enemy.y + 24, cellSize, paintGreen);
        break;

      case EnemyType.bigAlien:
      // Большая тварь - ЖЁЛТАЯ, в 3 раза больше, 12 щупалец
        const bigCellSize = 6.0;
        final paintYellow = Paint()..color = const Color(0xFFFFFF00);
        final paintRedBig = Paint()..color = const Color(0xFFFF3333);

        // Полупрозрачный красный круг при попадании - более заметный
        if (enemy.lastDamageTaken >= 0 && enemy.lastDamageTaken < 0.4) {
          canvas.drawCircle(
            Offset(enemy.x + 45, enemy.y + 30),
            65,
            Paint()
              ..color = const Color(0xFFFF0000).withOpacity(0.5)
              ..style = PaintingStyle.fill,
          );
          enemy.lastDamageTaken += 0.016;
        }

        // Голова большая
        _drawPixel(canvas, enemy.x + 30, enemy.y + 6, bigCellSize, paintYellow);
        _drawPixel(canvas, enemy.x + 36, enemy.y + 6, bigCellSize, paintYellow);
        _drawPixel(canvas, enemy.x + 42, enemy.y + 6, bigCellSize, paintYellow);
        _drawPixel(canvas, enemy.x + 48, enemy.y + 6, bigCellSize, paintYellow);
        _drawPixel(canvas, enemy.x + 54, enemy.y + 6, bigCellSize, paintYellow);
        _drawPixel(canvas, enemy.x + 60, enemy.y + 6, bigCellSize, paintYellow);

        _drawPixel(canvas, enemy.x + 24, enemy.y + 12, bigCellSize, paintYellow);
        _drawPixel(canvas, enemy.x + 30, enemy.y + 12, bigCellSize, paintRedBig); // Глаз
        _drawPixel(canvas, enemy.x + 36, enemy.y + 12, bigCellSize, paintYellow);
        _drawPixel(canvas, enemy.x + 42, enemy.y + 12, bigCellSize, paintYellow);
        _drawPixel(canvas, enemy.x + 48, enemy.y + 12, bigCellSize, paintYellow);
        _drawPixel(canvas, enemy.x + 54, enemy.y + 12, bigCellSize, paintRedBig); // Глаз
        _drawPixel(canvas, enemy.x + 60, enemy.y + 12, bigCellSize, paintYellow);
        _drawPixel(canvas, enemy.x + 66, enemy.y + 12, bigCellSize, paintYellow);

        _drawPixel(canvas, enemy.x + 30, enemy.y + 18, bigCellSize, paintYellow);
        _drawPixel(canvas, enemy.x + 36, enemy.y + 18, bigCellSize, paintYellow);
        _drawPixel(canvas, enemy.x + 42, enemy.y + 18, bigCellSize, paintYellow);
        _drawPixel(canvas, enemy.x + 48, enemy.y + 18, bigCellSize, paintYellow);
        _drawPixel(canvas, enemy.x + 54, enemy.y + 18, bigCellSize, paintYellow);
        _drawPixel(canvas, enemy.x + 60, enemy.y + 18, bigCellSize, paintYellow);

        // 12 щупалец (больше чем у обычной)
        for (int i = 0; i < 12; i++) {
          final xPos = enemy.x + 12 + (i * 6);
          _drawPixel(canvas, xPos, enemy.y + 24, bigCellSize, paintYellow);
          _drawPixel(canvas, xPos, enemy.y + 30, bigCellSize, paintYellow);
        }
        break;
    }
  }

  void _drawBonus(Canvas canvas, Bonus bonus) {
    final paintCyan = Paint()..color = const Color(0xFF00FFFF);
    final paintGreen = Paint()..color = const Color(0xFF00FF00);
    final paintRed = Paint()..color = const Color(0xFFFF0000);
    final paintPurple = Paint()..color = const Color(0xFF7700FF);

    final angle = (DateTime.now().millisecond / 1000) * 2 * math.pi;
    canvas.save();
    canvas.translate(bonus.x + 15, bonus.y + 10);
    canvas.rotate(angle);

    switch (bonus.type) {
      case 'fast_shot':
      // Молния - жёлтая
        final pathPaint = Paint()
          ..color = const Color(0xFFFFFF00)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        final path = Path()
          ..moveTo(-5, -8)
          ..lineTo(-2, 0)
          ..lineTo(3, 0)
          ..lineTo(0, 5)
          ..close();
        canvas.drawPath(path, pathPaint);
        break;
      case 'thick_bullet':
      // Коробка - фиолетовая
        final boxPaint = Paint()..color = const Color(0xFF7700FF);
        canvas.drawRect(Rect.fromLTWH(-6, -6, 12, 12), boxPaint);
        canvas.drawRect(Rect.fromLTWH(-4, -4, 8, 8), Paint()
          ..color = const Color(0xFF0a0e27)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
        break;
      case 'health':
      // Зелёный крест - здоровье
        final crossPaint = Paint()
          ..color = const Color(0xFF00FF00)
          ..strokeWidth = 2;
        canvas.drawLine(const Offset(-2, -6), const Offset(-2, 6), crossPaint);
        canvas.drawLine(const Offset(2, -6), const Offset(2, 6), crossPaint);
        canvas.drawLine(const Offset(-6, -2), const Offset(6, -2), crossPaint);
        canvas.drawLine(const Offset(-6, 2), const Offset(6, 2), crossPaint);
        break;
      case 'medkit':
      // Аптечка - белый крест на красном фоне
        final boxPaint = Paint()..color = const Color(0xFFFF0000);
        canvas.drawRect(Rect.fromLTWH(-8, -8, 16, 16), boxPaint);
        final crossPaint = Paint()
          ..color = const Color(0xFFFFFFFF)
          ..strokeWidth = 2;
        canvas.drawLine(const Offset(-4, 0), const Offset(4, 0), crossPaint);
        canvas.drawLine(const Offset(0, -4), const Offset(0, 4), crossPaint);
        break;
      case 'purple_bullets':
      // Коробка с фиолетовыми пулями
        final boxPaint = Paint()..color = const Color(0xFF7700FF);
        canvas.drawRect(Rect.fromLTWH(-8, -8, 16, 16), boxPaint);
        // Три точки внутри - пули
        canvas.drawCircle(const Offset(-3, 0), 2, Paint()..color = const Color(0xFFFFFF00));
        canvas.drawCircle(const Offset(0, 0), 2, Paint()..color = const Color(0xFFFFFF00));
        canvas.drawCircle(const Offset(3, 0), 2, Paint()..color = const Color(0xFFFFFF00));
        break;
    }
    canvas.restore();
  }

  void _drawHUD(Canvas canvas, Size size) {
    // Полупрозрачный фон для HUD
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(10, 10, 250, 80),
        const Radius.circular(5),
      ),
      Paint()
        ..color = const Color(0xFF000000).withOpacity(0.6),
    );

    // Обводка
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(10, 10, 250, 80),
        const Radius.circular(5),
      ),
      Paint()
        ..color = const Color(0xFF00FFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Score и Level
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Score: ${gameState.score}  Level: ${gameState.level}',
        style: const TextStyle(
          color: Color(0xFF00FFFF),
          fontSize: 14,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(20, 20));

    // Health отдельно, другим цветом
    final healthPainter = TextPainter(
      text: TextSpan(
        text: 'Health: ${gameState.health}',
        style: const TextStyle(
          color: Color(0xFFFF3333),
          fontSize: 14,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    healthPainter.layout();
    healthPainter.paint(canvas, const Offset(20, 50));
  }

  void _drawGameOver(Canvas canvas, Size size) {
    // Полупрозрачный фон
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0x99000000),
    );

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'GAME OVER',
        style: TextStyle(
          color: Color(0xFFFF00FF),
          fontSize: 48,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(size.width / 2 - textPainter.width / 2, size.height / 2 - 100),
    );

    final scorePainter = TextPainter(
      text: TextSpan(
        text: 'Final Score: ${gameState.score}\nLevel: ${gameState.level}',
        style: const TextStyle(
          color: Color(0xFF00FFFF),
          fontSize: 24,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    scorePainter.layout();
    scorePainter.paint(
      canvas,
      Offset(size.width / 2 - scorePainter.width / 2, size.height / 2 - 20),
    );

    // Кнопка Try Again
    const buttonWidth = 150.0;
    const buttonHeight = 50.0;
    final buttonX = size.width / 2 - buttonWidth / 2;
    final buttonY = size.height / 2 + 60;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(buttonX, buttonY, buttonWidth, buttonHeight),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFF00FFFF),
    );

    final buttonText = TextPainter(
      text: const TextSpan(
        text: 'TRY AGAIN',
        style: TextStyle(
          color: Color(0xFF000000),
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    buttonText.layout();
    buttonText.paint(
      canvas,
      Offset(buttonX + buttonWidth / 2 - buttonText.width / 2,
          buttonY + buttonHeight / 2 - buttonText.height / 2),
    );
  }

  @override
  bool shouldRepaint(GamePainter oldDelegate) => true;
}