// 第一人称射击游戏 - 类似吃鸡游戏
// 游戏状态管理
let game = {
    isRunning: false,
    isPaused: false,
    gameTime: 180, // 3分钟（180秒）
    enemyCount: 10,
    player: {
        health: 100,
        maxHealth: 100,
        ammo: 30,
        maxAmmo: 30,
        weapon: '突击步枪',
        position: { x: 0, y: 1.7, z: 0 },
        velocity: { x: 0, y: 0, z: 0 },
        speed: 5,
        isJumping: false,
        rotation: { x: 0, y: 0 }
    },
    enemies: [],
    bullets: [],
    pickups: []
};

// Three.js相关变量
let scene, camera, renderer;
let world, playerBody;
let clock = new THREE.Clock();
let keys = {};
let mouse = { x: 0, y: 0 };
let isMouseLocked = false;
let mouseSensitivity = 0.002;

// 移动设备控制变量
let isTouchDevice = 'ontouchstart' in window || navigator.maxTouchPoints > 0;
let joystickActive = false;
let joystickPosition = { x: 0, y: 0 };
let joystickTouchId = null;
let lookTouchActive = false;
let lookTouchId = null;
let lastLookX = 0;
let lastLookY = 0;
let touchKeys = {};

// 游戏对象
let ground, skybox;
let enemyMeshes = [];
let bulletMeshes = [];
let pickupMeshes = [];

// 初始化游戏
function init() {
    // 创建Three.js场景
    scene = new THREE.Scene();
    scene.fog = new THREE.Fog(0x87CEEB, 10, 500);
    
    // 创建相机
    camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
    camera.position.set(0, 1.7, 0);
    
    // 创建渲染器
    const canvas = document.getElementById('gameCanvas');
    if (!canvas) {
        throw new Error('Canvas元素未找到，请检查HTML结构');
    }
    
    try {
        renderer = new THREE.WebGLRenderer({ 
            canvas: canvas, 
            antialias: true,
            alpha: true,
            powerPreference: 'high-performance'
        });
        renderer.setSize(window.innerWidth, window.innerHeight);
        renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2)); // 限制像素比以提高性能
        renderer.shadowMap.enabled = true;
        renderer.shadowMap.type = THREE.PCFSoftShadowMap;
        
        console.log('WebGL渲染器创建成功，支持WebGL版本:', renderer.capabilities.version);
        updateDebugInfo(`WebGL渲染器创建成功 (${renderer.capabilities.version})`);
    } catch (error) {
        throw new Error('无法创建WebGL渲染器: ' + error.message);
    }
    
        // 检查Cannon.js是否可用
    if (!window.CANNON) {
        console.warn('Cannon.js 物理引擎未加载，跳过物理世界创建...');
        updateDebugInfo('注意: 物理引擎未加载，部分功能受限');
        
        // 创建虚拟物理世界占位，防止后续代码出错
        world = {
            gravity: { set: () => {} },
            broadphase: {},
            solver: { iterations: 10 },
            addBody: () => {},
            removeBody: () => {},
            step: () => {}
        };
        
        // 创建虚拟玩家物理体
        playerBody = {
            position: { x: 0, y: 5, z: 0 },
            velocity: { x: 0, y: 0, z: 0 },
            quaternion: { x: 0, y: 0, z: 0, w: 1 },
            angularVelocity: { x: 0, y: 0, z: 0 },
            applyForce: () => {},
            applyImpulse: () => {},
            updateMassProperties: () => {}
        };
    } else {
        // 创建Cannon.js物理世界
        world = new CANNON.World();
        world.gravity.set(0, -9.82, 0);
        world.broadphase = new CANNON.NaiveBroadphase();
        world.solver.iterations = 10;
        
        // 创建物理地面
        const groundShape = new CANNON.Plane();
        const groundBody = new CANNON.Body({ mass: 0 });
        groundBody.addShape(groundShape);
        groundBody.quaternion.setFromAxisAngle(new CANNON.Vec3(1, 0, 0), -Math.PI / 2);
        world.addBody(groundBody);
        
        // 创建玩家物理体
        const playerShape = new CANNON.Sphere(0.5);
        playerBody = new CANNON.Body({ mass: 70 });
        playerBody.addShape(playerShape);
        playerBody.position.set(0, 5, 0);
        playerBody.linearDamping = 0.9;
        world.addBody(playerBody);
    }
    
    // 创建3D地面（无论物理引擎是否加载都创建）
    const groundGeometry = new THREE.PlaneGeometry(500, 500, 100, 100);
    const groundMaterial = new THREE.MeshLambertMaterial({ 
        color: 0x3a7c3a,
        side: THREE.DoubleSide
    });
    ground = new THREE.Mesh(groundGeometry, groundMaterial);
    ground.rotation.x = -Math.PI / 2;
    ground.receiveShadow = true;
    scene.add(ground);
    
    // 创建天空盒
    createSkybox();
    
    // 添加光源
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.5);
    scene.add(ambientLight);
    
    const directionalLight = new THREE.DirectionalLight(0xffffff, 0.8);
    directionalLight.position.set(100, 100, 50);
    directionalLight.castShadow = true;
    directionalLight.shadow.mapSize.width = 2048;
    directionalLight.shadow.mapSize.height = 2048;
    scene.add(directionalLight);
    
    // 创建随机地形元素
    createTerrainElements();
    
    // 创建敌人
    createEnemies();
    
    // 创建物品拾取
    createPickups();
    
    // 设置事件监听器
    setupEventListeners();
    
    // 更新UI
    updateUI();
    
    console.log('游戏初始化完成！');
    updateDebugInfo('3D场景创建完成');
    
    // 开始游戏循环（即使游戏未开始也需要渲染场景）
    animate();
}

// 创建天空盒
function createSkybox() {
    const skyGeometry = new THREE.SphereGeometry(1000, 32, 32);
    const skyMaterial = new THREE.MeshBasicMaterial({
        color: 0x87CEEB,
        side: THREE.BackSide
    });
    skybox = new THREE.Mesh(skyGeometry, skyMaterial);
    scene.add(skybox);
}

// 创建地形元素
function createTerrainElements() {
    // 创建一些树木
    for (let i = 0; i < 50; i++) {
        const treeGeometry = new THREE.CylinderGeometry(0.5, 1, 5, 8);
        const treeMaterial = new THREE.MeshLambertMaterial({ color: 0x8B4513 });
        const tree = new THREE.Mesh(treeGeometry, treeMaterial);
        
        const x = (Math.random() - 0.5) * 400;
        const z = (Math.random() - 0.5) * 400;
        tree.position.set(x, 2.5, z);
        tree.castShadow = true;
        scene.add(tree);
        
        // 创建树冠
        const leavesGeometry = new THREE.SphereGeometry(2, 8, 8);
        const leavesMaterial = new THREE.MeshLambertMaterial({ color: 0x228B22 });
        const leaves = new THREE.Mesh(leavesGeometry, leavesMaterial);
        leaves.position.set(0, 4, 0);
        tree.add(leaves);
    }
    
    // 创建一些岩石
    for (let i = 0; i < 30; i++) {
        const rockGeometry = new THREE.SphereGeometry(1 + Math.random() * 2, 6, 6);
        const rockMaterial = new THREE.MeshLambertMaterial({ color: 0x808080 });
        const rock = new THREE.Mesh(rockGeometry, rockMaterial);
        
        const x = (Math.random() - 0.5) * 400;
        const z = (Math.random() - 0.5) * 400;
        rock.position.set(x, 1, z);
        rock.castShadow = true;
        scene.add(rock);
    }
    
    // 创建一些建筑物
    for (let i = 0; i < 10; i++) {
        const buildingWidth = 5 + Math.random() * 10;
        const buildingHeight = 5 + Math.random() * 15;
        const buildingDepth = 5 + Math.random() * 10;
        
        const buildingGeometry = new THREE.BoxGeometry(buildingWidth, buildingHeight, buildingDepth);
        const buildingMaterial = new THREE.MeshLambertMaterial({ color: 0x696969 });
        const building = new THREE.Mesh(buildingGeometry, buildingMaterial);
        
        const x = (Math.random() - 0.5) * 400;
        const z = (Math.random() - 0.5) * 400;
        building.position.set(x, buildingHeight / 2, z);
        building.castShadow = true;
        scene.add(building);
    }
}

// 创建敌人
function createEnemies() {
    for (let i = 0; i < game.enemyCount; i++) {
        const enemy = {
            id: i,
            health: 100,
            position: {
                x: (Math.random() - 0.5) * 300,
                y: 1,
                z: (Math.random() - 0.5) * 300
            },
            target: null,
            state: 'patrol', // patrol, chase, attack
            patrolTimer: Math.random() * 5
        };
        
        game.enemies.push(enemy);
        
        // 创建敌人3D模型
        const enemyGeometry = new THREE.CylinderGeometry(0.5, 0.5, 1.8, 8);
        const enemyMaterial = new THREE.MeshLambertMaterial({ color: 0xff0000 });
        const enemyMesh = new THREE.Mesh(enemyGeometry, enemyMaterial);
        enemyMesh.position.set(enemy.position.x, 0.9, enemy.position.z);
        enemyMesh.castShadow = true;
        scene.add(enemyMesh);
        enemyMeshes.push(enemyMesh);
    }
}

// 创建物品拾取
function createPickups() {
    const pickupTypes = [
        { type: 'health', color: 0xff0000, amount: 50 },
        { type: 'ammo', color: 0xffff00, amount: 30 },
        { type: 'weapon', color: 0x00ff00, amount: 1 }
    ];
    
    for (let i = 0; i < 20; i++) {
        const pickupType = pickupTypes[Math.floor(Math.random() * pickupTypes.length)];
        const pickup = {
            type: pickupType.type,
            amount: pickupType.amount,
            position: {
                x: (Math.random() - 0.5) * 400,
                y: 0.5,
                z: (Math.random() - 0.5) * 400
            },
            collected: false
        };
        
        game.pickups.push(pickup);
        
        // 创建拾取物3D模型
        const pickupGeometry = new THREE.SphereGeometry(0.5, 8, 8);
        const pickupMaterial = new THREE.MeshLambertMaterial({ color: pickupType.color });
        const pickupMesh = new THREE.Mesh(pickupGeometry, pickupMaterial);
        pickupMesh.position.set(pickup.position.x, pickup.position.y, pickup.position.z);
        pickupMesh.castShadow = true;
        scene.add(pickupMesh);
        pickupMeshes.push(pickupMesh);
    }
}

// 设置事件监听器
function setupEventListeners() {
    // 检测是否为移动设备
    console.log('设备检测: ', isTouchDevice ? '移动设备' : '桌面设备');
    
    // 键盘事件（桌面端）
    if (!isTouchDevice) {
        document.addEventListener('keydown', (e) => {
            keys[e.code] = true;
            
            // 重新装弹
            if (e.code === 'KeyR' && game.isRunning) {
                reloadWeapon();
            }
            
            // 暂停游戏
            if (e.code === 'Escape') {
                togglePause();
            }
        });
        
        document.addEventListener('keyup', (e) => {
            keys[e.code] = false;
        });
        
        // 鼠标事件（桌面端）
        document.addEventListener('mousedown', (e) => {
            if (game.isRunning && !game.isPaused) {
                shoot();
            }
        });
        
        document.addEventListener('mousemove', (e) => {
            if (game.isRunning && !game.isPaused) {
                const movementX = e.movementX || e.mozMovementX || e.webkitMovementX || 0;
                const movementY = e.movementY || e.mozMovementY || e.webkitMovementY || 0;
                
                game.player.rotation.y -= movementX * mouseSensitivity;
                game.player.rotation.x -= movementY * mouseSensitivity;
                
                // 限制垂直视角
                game.player.rotation.x = Math.max(-Math.PI/2, Math.min(Math.PI/2, game.player.rotation.x));
            }
        });
    }
    
    // 触摸事件（移动端）
    if (isTouchDevice) {
        setupMobileControls();
    }
    
    // 窗口大小调整（通用）
    window.addEventListener('resize', () => {
        camera.aspect = window.innerWidth / window.innerHeight;
        camera.updateProjectionMatrix();
        renderer.setSize(window.innerWidth, window.innerHeight);
    });
}

// 设置移动设备控制 - 绝地求生风格
function setupMobileControls() {
    console.log('设置移动设备控制（绝地求生风格）...');
    
    const joystickContainer = document.getElementById('joystickContainer');
    const joystickHandle = document.getElementById('joystickHandle');
    const lookArea = document.getElementById('lookArea');
    const shootButton = document.getElementById('shootButton');
    const jumpButton = document.getElementById('jumpButton');
    const reloadButton = document.getElementById('reloadButton');
    
    // 虚拟摇杆控制
    let joystickStartX = 0;
    let joystickStartY = 0;
    let joystickRadius = 75;
    let joystickTouchId = null;
    
    joystickContainer.addEventListener('touchstart', (e) => {
        e.preventDefault();
        if (e.touches.length > 0) {
            joystickActive = true;
            joystickTouchId = e.touches[0].identifier;
            
            const rect = joystickContainer.getBoundingClientRect();
            joystickStartX = rect.left + rect.width / 2;
            joystickStartY = rect.top + rect.height / 2;
            
            updateJoystickPosition(e.touches[0]);
        }
    });
    
    // 射击按钮 - 触摸事件优先处理（解决lookArea拦截问题）
    function handleShoot(e) {
        e.preventDefault();
        e.stopPropagation();
        
        console.log('🎯 射击按钮触发！');
        console.log('  游戏状态:', {isRunning: game.isRunning, isPaused: game.isPaused, ammo: game.player.ammo});
        
        if (game.isRunning && !game.isPaused && game.player.ammo > 0) {
            shoot();
            console.log('✅ 射击成功执行！');
        } else if (game.player.ammo <= 0) {
            console.log('⚠️ 弹药不足，需要装弹！');
            // 震动反馈
            if (navigator.vibrate) {
                navigator.vibrate([50, 30, 50]);
            }
        } else {
            console.log('⚠️ 游戏未开始或已暂停，无法射击');
        }
    }
    
    // 直接添加到window确保事件能被捕获
    shootButton.addEventListener('touchstart', handleShoot, { passive: false });
    shootButton.addEventListener('mousedown', handleShoot);
    
    // 使用capture阶段优先捕获
    shootButton.addEventListener('touchstart', handleShoot, { capture: true, passive: false });
    
    // 防止触摸事件穿透到lookArea
    shootButton.addEventListener('touchend', (e) => {
        e.preventDefault();
        e.stopPropagation();
    }, { capture: true, passive: false });
    
    // 额外：全局触摸事件处理射击（防止按钮被遮挡）
    document.addEventListener('touchstart', (e) => {
        if (e.target === shootButton || shootButton.contains(e.target)) {
            handleShoot(e);
        }
    }, { passive: true });
    
    jumpButton.addEventListener('touchstart', (e) => {
        e.preventDefault();
        touchKeys['jump'] = true;
    });
    
    jumpButton.addEventListener('touchend', (e) => {
        e.preventDefault();
        touchKeys['jump'] = false;
    });
    
    reloadButton.addEventListener('touchstart', (e) => {
        e.preventDefault();
        if (game.isRunning && !game.isPaused) {
            reloadWeapon();
        }
    });
    
    // 全局触摸移动处理 - 同时支持移动和视野控制
    document.addEventListener('touchmove', (e) => {
        // 遍历所有触摸点，分别处理
        for (let i = 0; i < e.touches.length; i++) {
            const touch = e.touches[i];
            const touchX = touch.clientX;
            const touchY = touch.clientY;
            
            // 处理摇杆移动（左侧区域）
            if (joystickActive && touch.identifier === joystickTouchId) {
                e.preventDefault();
                updateJoystickPosition(touch);
            }
            
            // 处理视野控制（右侧区域）
            if (lookTouchActive && touch.identifier === lookTouchId) {
                e.preventDefault();
                const deltaX = touch.clientX - lastLookX;
                const deltaY = touch.clientY - lastLookY;
                
                // 灵敏度调整，像绝地求生一样
                game.player.rotation.y -= deltaX * mouseSensitivity * 3;
                game.player.rotation.x -= deltaY * mouseSensitivity * 3;
                
                // 限制垂直视角范围
                game.player.rotation.x = Math.max(-Math.PI/2.2, Math.min(Math.PI/2.2, game.player.rotation.x));
                
                lastLookX = touch.clientX;
                lastLookY = touch.clientY;
            }
        }
    }, { passive: false });
    
    document.addEventListener('touchend', (e) => {
        // 检查摇杆释放
        if (joystickActive && joystickTouchId !== null) {
            let found = false;
            for (let i = 0; i < e.touches.length; i++) {
                if (e.touches[i].identifier === joystickTouchId) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                joystickActive = false;
                joystickTouchId = null;
                joystickPosition.x = 0;
                joystickPosition.y = 0;
                joystickHandle.style.transform = 'translate(-50%, -50%)';
                console.log('摇杆释放');
            }
        }
        
        // 检查视角触摸释放
        if (lookTouchActive && lookTouchId !== null) {
            let found = false;
            for (let i = 0; i < e.touches.length; i++) {
                if (e.touches[i].identifier === lookTouchId) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                lookTouchActive = false;
                lookTouchId = null;
                console.log('视野控制结束');
            }
        }
    });
    
    document.addEventListener('touchcancel', (e) => {
        // 处理触摸取消（如来电等情况）
        joystickActive = false;
        joystickTouchId = null;
        joystickPosition.x = 0;
        joystickPosition.y = 0;
        joystickHandle.style.transform = 'translate(-50%, -50%)';
        
        lookTouchActive = false;
        lookTouchId = null;
    });
    
    function updateJoystickPosition(touch) {
        const touchX = touch.clientX;
        const touchY = touch.clientY;
        
        let deltaX = touchX - joystickStartX;
        let deltaY = touchY - joystickStartY;
        
        // 限制在摇杆范围内
        const distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
        if (distance > joystickRadius) {
            deltaX = (deltaX / distance) * joystickRadius;
            deltaY = (deltaY / distance) * joystickRadius;
        }
        
        joystickPosition.x = deltaX / joystickRadius;
        joystickPosition.y = deltaY / joystickRadius;
        
        // 更新摇杆手柄位置
        joystickHandle.style.transform = `translate(calc(-50% + ${deltaX}px), calc(-50% + ${deltaY}px))`;
    }
    
    // 视角控制区域 - 右侧屏幕
    lookArea.addEventListener('touchstart', (e) => {
        e.preventDefault();
        
        // 检查触摸位置是否在右侧控制按钮区域内
        const touch = e.touches[0];
        const rightControlsRect = shootButton.getBoundingClientRect();
        const jumpRect = jumpButton.getBoundingClientRect();
        const reloadRect = reloadButton.getBoundingClientRect();
        
        // 如果触摸在按钮区域，不处理视角
        if ((touch.clientX >= rightControlsRect.left && touch.clientX <= rightControlsRect.right &&
             touch.clientY >= rightControlsRect.top && touch.clientY <= rightControlsRect.bottom) ||
            (touch.clientX >= jumpRect.left && touch.clientX <= jumpRect.right &&
             touch.clientY >= jumpRect.top && touch.clientY <= jumpRect.bottom) ||
            (touch.clientX >= reloadRect.left && touch.clientX <= reloadRect.right &&
             touch.clientY >= reloadRect.top && touch.clientY <= reloadRect.bottom)) {
            console.log('触摸在按钮区域，跳过视角控制');
            return;
        }
        
        if (e.touches.length > 0 && !lookTouchActive) {
            lookTouchActive = true;
            lookTouchId = e.touches[0].identifier;
            lastLookX = e.touches[0].clientX;
            lastLookY = e.touches[0].clientY;
            console.log('视角触摸开始');
        }
    });
    
    console.log('移动设备控制设置完成');
}

// 开始游戏
function startGame() {
    console.log('开始游戏按钮点击');
    updateDebugInfo('开始游戏按钮被点击...');
    
    // 检查游戏是否已经初始化
    if (!scene || !camera || !renderer) {
        updateDebugInfo('错误: 游戏未正确初始化，请刷新页面');
        alert('游戏未正确初始化，请刷新页面');
        return;
    }
    
    if (!game.isRunning) {
        console.log('启动游戏...');
        updateDebugInfo('正在启动游戏...');
        
        game.isRunning = true;
        game.isPaused = false;
        
        // 重置游戏状态
        resetGame();
        
        // 隐藏开始屏幕
        document.getElementById('startScreen').classList.add('hidden');
        
        // 如果是移动设备，显示移动控制
        if (isTouchDevice) {
            document.body.classList.add('game-running');
            console.log('游戏运行类已添加，移动控制应该显示');
            updateDebugInfo('移动控制已启用');
        }
        
        console.log('游戏开始！状态: running =', game.isRunning);
        updateDebugInfo('游戏已启动！');
        
        // 确保游戏循环运行
        if (!game.isPaused) {
            console.log('启动游戏循环...');
            animate();
        }
    } else {
        console.log('游戏已经在运行中');
        updateDebugInfo('游戏已经在运行中');
    }
}

// 重置游戏
function resetGame() {
    game.gameTime = 180; // 3分钟
    game.enemyCount = 10;
    game.player.health = 100;
    game.player.ammo = 30;
    
    // 重置玩家位置
    playerBody.position.set(0, 5, 0);
    playerBody.velocity.set(0, 0, 0);
    
    // 重置敌人
    game.enemies = [];
    enemyMeshes.forEach(mesh => scene.remove(mesh));
    enemyMeshes = [];
    createEnemies();
    
    // 隐藏游戏结束屏幕
    document.getElementById('gameOverScreen').classList.add('hidden');
    
    // 更新UI
    updateUI();
}

// 重新开始游戏
function restartGame() {
    resetGame();
    game.isRunning = true;
    game.isPaused = false;
    document.getElementById('gameOverScreen').classList.add('hidden');
    
    // 如果是移动设备，显示移动控制
    if (isTouchDevice) {
        document.getElementById('mobileControls').style.display = 'block';
    }
    
    console.log('游戏重新开始');
    updateDebugInfo('游戏重新开始');
}

// 暂停游戏
function togglePause() {
    if (game.isRunning) {
        game.isPaused = !game.isPaused;
        
        if (game.isPaused) {
            document.getElementById('crosshair').style.display = 'none';
        } else {
            document.getElementById('crosshair').style.display = 'block';
        }
    }
}

// 更新UI
function updateUI() {
    // 更新生命值
    document.getElementById('healthText').textContent = Math.max(0, game.player.health);
    document.getElementById('healthFill').style.width = `${(game.player.health / game.player.maxHealth) * 100}%`;
    
    // 更新弹药
    document.getElementById('currentAmmo').textContent = game.player.ammo;
    document.getElementById('maxAmmo').textContent = game.player.maxAmmo;
    
    // 更新武器信息
    document.getElementById('weaponName').textContent = game.player.weapon;
    
    // 更新敌人计数
    document.getElementById('enemyCounter').textContent = game.enemyCount;
    
    // 更新时间
    const minutes = Math.floor(game.gameTime / 60);
    const seconds = Math.floor(game.gameTime % 60);
    document.getElementById('timeCounter').textContent = 
        `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
}

// 射击
function shoot() {
    console.log('射击函数被调用，游戏状态:', {
        ammo: game.player.ammo,
        isRunning: game.isRunning,
        isPaused: game.isPaused,
        ammoCondition: game.player.ammo > 0,
        runningCondition: game.isRunning,
        pausedCondition: !game.isPaused
    });
    
    if (game.player.ammo > 0 && game.isRunning && !game.isPaused) {
        // 减少弹药
        game.player.ammo--;
        
        // 创建子弹
        const bullet = {
            position: camera.position.clone(),
            direction: new THREE.Vector3(),
            speed: 100,
            damage: 25,
            lifeTime: 2.0
        };
        
        // 设置子弹方向（从相机前方发射）
        camera.getWorldDirection(bullet.direction);
        bullet.direction.normalize();
        
        // 偏移一点位置，避免打到自己
        bullet.position.add(bullet.direction.clone().multiplyScalar(0.5));
        
        game.bullets.push(bullet);
        
        // 创建子弹3D模型
        const bulletGeometry = new THREE.SphereGeometry(0.05, 8, 8);
        const bulletMaterial = new THREE.MeshBasicMaterial({ color: 0xffff00 });
        const bulletMesh = new THREE.Mesh(bulletGeometry, bulletMaterial);
        bulletMesh.position.copy(bullet.position);
        scene.add(bulletMesh);
        bulletMeshes.push(bulletMesh);
        
        // 后坐力效果
        game.player.rotation.x -= 0.02;
        
        // 检测命中
        checkBulletHits(bullet);
        
        // 更新UI
        updateUI();
        
        console.log('射击成功！剩余弹药：' + game.player.ammo);
        
        // 添加射击视觉反馈（屏幕闪烁）
        document.getElementById('crosshair').style.backgroundColor = '#ff0000';
        setTimeout(() => {
            document.getElementById('crosshair').style.backgroundColor = '#ffffff';
        }, 100);
    } else if (game.player.ammo <= 0) {
        console.log('弹药耗尽！按R键或点击装弹按钮重新装弹');
        // 添加弹药耗尽反馈
        document.getElementById('currentAmmo').style.color = '#ff0000';
        setTimeout(() => {
            document.getElementById('currentAmmo').style.color = '#ffffff';
        }, 500);
    } else if (!game.isRunning) {
        console.log('游戏未开始，无法射击');
    } else if (game.isPaused) {
        console.log('游戏已暂停，无法射击');
    }
}

// 检测子弹命中
function checkBulletHits(bullet) {
    const raycaster = new THREE.Raycaster(bullet.position, bullet.direction, 0, 100);
    
    // 检测敌人
    for (let i = 0; i < enemyMeshes.length; i++) {
        const enemyMesh = enemyMeshes[i];
        const intersects = raycaster.intersectObject(enemyMesh);
        
        if (intersects.length > 0 && game.enemies[i].health > 0) {
            // 击中敌人
            game.enemies[i].health -= bullet.damage;
            
            if (game.enemies[i].health <= 0) {
                // 敌人死亡
                enemyMesh.material.color.set(0x888888);
                game.enemyCount--;
                
                if (game.enemyCount <= 0) {
                    gameOver(true);
                }
            } else {
                // 敌人受伤
                enemyMesh.material.color.set(0xff6666);
                setTimeout(() => {
                    enemyMesh.material.color.set(0xff0000);
                }, 100);
            }
            
            updateUI();
            break;
        }
    }
}

// 重新装弹
function reloadWeapon() {
    if (game.player.ammo < game.player.maxAmmo) {
        const ammoNeeded = game.player.maxAmmo - game.player.ammo;
        game.player.ammo += ammoNeeded;
        console.log('重新装弹！当前弹药：' + game.player.ammo);
        updateUI();
    }
}

// 敌人AI
function updateEnemies(deltaTime) {
    for (let i = 0; i < game.enemies.length; i++) {
        const enemy = game.enemies[i];
        const enemyMesh = enemyMeshes[i];
        
        if (enemy.health <= 0) continue;
        
        // 计算与玩家的距离
        const playerPos = playerBody.position;
        const enemyPos = enemy.position;
        const distanceToPlayer = Math.sqrt(
            Math.pow(playerPos.x - enemyPos.x, 2) +
            Math.pow(playerPos.z - enemyPos.z, 2)
        );
        
        // 更新敌人状态
        if (distanceToPlayer < 10) {
            enemy.state = 'attack';
        } else if (distanceToPlayer < 50) {
            enemy.state = 'chase';
        } else {
            enemy.state = 'patrol';
        }
        
        // 根据状态行动
        switch (enemy.state) {
            case 'patrol':
                enemy.patrolTimer -= deltaTime;
                if (enemy.patrolTimer <= 0) {
                    // 随机移动
                    enemy.position.x += (Math.random() - 0.5) * 5;
                    enemy.position.z += (Math.random() - 0.5) * 5;
                    enemy.patrolTimer = 2 + Math.random() * 3;
                }
                break;
                
            case 'chase':
                // 向玩家移动
                const dx = playerPos.x - enemyPos.x;
                const dz = playerPos.z - enemyPos.z;
                const distance = Math.sqrt(dx * dx + dz * dz);
                
                if (distance > 2) {
                    enemy.position.x += (dx / distance) * 5 * deltaTime;
                    enemy.position.z += (dz / distance) * 5 * deltaTime;
                }
                break;
                
            case 'attack':
                // 攻击玩家
                if (Math.random() < 0.1 * deltaTime) {
                    takeDamage(10);
                }
                break;
        }
        
        // 更新敌人位置
        enemyMesh.position.set(enemy.position.x, 0.9, enemy.position.z);
        
        // 检查与玩家的碰撞
        if (distanceToPlayer < 3) {
            takeDamage(5 * deltaTime);
            
            // 敌人被推开
            const pushForce = 2;
            const dx = enemyPos.x - playerPos.x;
            const dz = enemyPos.z - playerPos.z;
            const pushDistance = Math.sqrt(dx * dx + dz * dz);
            
            if (pushDistance > 0) {
                enemy.position.x += (dx / pushDistance) * pushForce * deltaTime;
                enemy.position.z += (dz / pushDistance) * pushForce * deltaTime;
            }
        }
    }
}

// 玩家受伤
function takeDamage(amount) {
    if (game.isRunning && !game.isPaused) {
        game.player.health -= amount;
        
        // 更新UI
        updateUI();
        
        // 屏幕闪烁红色效果
        document.body.style.backgroundColor = '#ff0000';
        setTimeout(() => {
            document.body.style.backgroundColor = '#111';
        }, 100);
        
        // 检查玩家死亡
        if (game.player.health <= 0) {
            game.player.health = 0;
            gameOver(false);
        } else {
            // 生命值自动恢复（缓慢）
            if (game.player.health < game.player.maxHealth) {
                game.player.health = Math.min(game.player.maxHealth, game.player.health + 0.5 * deltaTime);
            }
        }
    }
}

// 更新子弹
function updateBullets(deltaTime) {
    for (let i = game.bullets.length - 1; i >= 0; i--) {
        const bullet = game.bullets[i];
        const bulletMesh = bulletMeshes[i];
        
        // 更新子弹位置
        bullet.position.x += bullet.direction.x * bullet.speed * deltaTime;
        bullet.position.y += bullet.direction.y * bullet.speed * deltaTime;
        bullet.position.z += bullet.direction.z * bullet.speed * deltaTime;
        
        bulletMesh.position.set(bullet.position.x, bullet.position.y, bullet.position.z);
        
        // 减少子弹生命周期
        bullet.lifeTime -= deltaTime;
        
        // 移除过期子弹
        if (bullet.lifeTime <= 0) {
            game.bullets.splice(i, 1);
            scene.remove(bulletMesh);
            bulletMeshes.splice(i, 1);
        }
    }
}

// 更新拾取物
function updatePickups() {
    const playerPos = playerBody.position;
    
    for (let i = 0; i < game.pickups.length; i++) {
        const pickup = game.pickups[i];
        const pickupMesh = pickupMeshes[i];
        
        if (pickup.collected) continue;
        
        // 计算距离
        const distance = Math.sqrt(
            Math.pow(playerPos.x - pickup.position.x, 2) +
            Math.pow(playerPos.z - pickup.position.z, 2)
        );
        
        // 拾取物品
        if (distance < 2) {
            pickup.collected = true;
            
            switch (pickup.type) {
                case 'health':
                    game.player.health = Math.min(game.player.maxHealth, game.player.health + pickup.amount);
                    console.log('拾取生命值！当前生命：' + game.player.health);
                    break;
                    
                case 'ammo':
                    game.player.ammo = Math.min(game.player.maxAmmo, game.player.ammo + pickup.amount);
                    console.log('拾取弹药！当前弹药：' + game.player.ammo);
                    break;
                    
                case 'weapon':
                    game.player.weapon = '高级武器';
                    console.log('拾取新武器！');
                    break;
            }
            
            // 隐藏拾取物
            pickupMesh.visible = false;
            
            // 更新UI
            updateUI();
        }
    }
}

// 游戏结束
function gameOver(isWin) {
    game.isRunning = false;
    
    // 显示游戏结束屏幕
    const gameOverScreen = document.getElementById('gameOverScreen');
    const gameResult = document.getElementById('gameResult');
    const gameStats = document.getElementById('gameStats');
    
    if (isWin) {
        gameResult.textContent = '恭喜！你消灭了所有敌人！';
        gameResult.style.color = '#00ff00';
        console.log('游戏胜利！');
        updateDebugInfo('游戏胜利！');
    } else {
        gameResult.textContent = '游戏结束！你被击败了。';
        gameResult.style.color = '#ff0000';
        console.log('游戏失败');
        updateDebugInfo('游戏失败');
    }
    
    // 显示游戏统计
    const timeLeft = Math.floor(game.gameTime);
    const minutes = Math.floor(timeLeft / 60);
    const seconds = timeLeft % 60;
    const timeUsed = 900 - timeLeft;
    const minutesUsed = Math.floor(timeUsed / 60);
    const secondsUsed = timeUsed % 60;
    
    gameStats.textContent = `用时: ${minutesUsed}:${secondsUsed.toString().padStart(2, '0')} | 剩余生命: ${Math.floor(game.player.health)} | 剩余弹药: ${game.player.ammo}`;
    gameStats.style.color = '#ffff00';
    
    gameOverScreen.classList.remove('hidden');
    
    // 如果是移动设备，隐藏移动控制
    if (isTouchDevice) {
        document.body.classList.remove('game-running');
    }
}

// 显示开始屏幕
function showStartScreen() {
    game.isRunning = false;
    game.isPaused = false;
    
    // 隐藏游戏结束屏幕
    document.getElementById('gameOverScreen').classList.add('hidden');
    
    // 如果是移动设备，隐藏移动控制
    if (isTouchDevice) {
        document.body.classList.remove('game-running');
    }
    
    // 显示开始屏幕
    document.getElementById('startScreen').classList.remove('hidden');
    
    console.log('返回主菜单');
    updateDebugInfo('已返回主菜单');
}

// 全屏切换
function toggleFullscreen() {
    const elem = document.documentElement;
    if (!document.fullscreenElement && !document.webkitFullscreenElement && !document.mozFullScreenElement) {
        if (elem.requestFullscreen) {
            elem.requestFullscreen();
        } else if (elem.webkitRequestFullscreen) {
            elem.webkitRequestFullscreen();
        } else if (elem.mozRequestFullScreen) {
            elem.mozRequestFullScreen();
        }
        document.getElementById('fullscreenButton').textContent = '退出全屏';
    } else {
        if (document.exitFullscreen) {
            document.exitFullscreen();
        } else if (document.webkitExitFullscreen) {
            document.webkitExitFullscreen();
        } else if (document.mozCancelFullScreen) {
            document.mozCancelFullScreen();
        }
        document.getElementById('fullscreenButton').textContent = '全屏';
    }
}

// 横屏检测
function checkOrientation() {
    if (isTouchDevice) {
        const landscapeWarning = document.getElementById('landscapeWarning');
        if (window.innerHeight > window.innerWidth) {
            // 竖屏，显示提示
            landscapeWarning.style.display = 'flex';
        } else {
            // 横屏，隐藏提示
            landscapeWarning.style.display = 'none';
        }
    }
}

// 初始化横屏检测
window.addEventListener('load', () => {
    setTimeout(checkOrientation, 100);
});
window.addEventListener('resize', checkOrientation);
window.addEventListener('orientationchange', checkOrientation);

// 处理玩家输入
function handlePlayerInput(deltaTime) {
    if (!game.isRunning || game.isPaused) return;
    
    const moveSpeed = (keys['ShiftLeft'] || touchKeys['run']) ? 10 : game.player.speed;
    const velocity = new THREE.Vector3();
    
    if (isTouchDevice) {
        // 移动设备控制：虚拟摇杆
        // 修正：向上推摇杆（Y负值）= 前进，X正值 = 右移
        velocity.x = joystickPosition.x;  // 左负右正
        velocity.z = joystickPosition.y; // 向上推(负值)前进，向下拉(正值)后退
        
        // 跳跃按钮
        if (touchKeys['jump'] && !game.player.isJumping && playerBody.position.y < 2) {
            playerBody.velocity.y = 8;
            game.player.isJumping = true;
            console.log('跳跃触发！');
        }
    } else {
        // 桌面设备控制：键盘
        // 前后移动（W/S）
        if (keys['KeyW']) velocity.z -= 1;
        if (keys['KeyS']) velocity.z += 1;
        
        // 左右移动（A/D）
        if (keys['KeyA']) velocity.x -= 1;
        if (keys['KeyD']) velocity.x += 1;
        
        // 跳跃（空格键）
        if (keys['Space'] && !game.player.isJumping && playerBody.position.y < 2) {
            playerBody.velocity.y = 8;
            game.player.isJumping = true;
        }
    }
    
    // 应用移动
    if (velocity.length() > 0) {
        velocity.normalize();
        
        // 根据相机方向旋转移动向量
        const cameraDirection = new THREE.Vector3();
        camera.getWorldDirection(cameraDirection);
        cameraDirection.y = 0;
        cameraDirection.normalize();
        
        const rightVector = new THREE.Vector3().crossVectors(cameraDirection, new THREE.Vector3(0, 1, 0));
        
        const moveVector = new THREE.Vector3();
        moveVector.add(cameraDirection.clone().multiplyScalar(-velocity.z * moveSpeed));
        moveVector.add(rightVector.clone().multiplyScalar(velocity.x * moveSpeed));
        
        // 保持垂直速度不变
        moveVector.y = playerBody.velocity.y;
        
        playerBody.velocity.copy(moveVector);
    } else {
        // 如果没有输入，保持垂直速度不变，水平速度逐渐减小
        playerBody.velocity.x *= 0.9;
        playerBody.velocity.z *= 0.9;
    }
    
    // 更新跳跃状态
    if (playerBody.position.y < 1.5 && Math.abs(playerBody.velocity.y) < 0.1) {
        game.player.isJumping = false;
        if (isTouchDevice) {
            touchKeys['jump'] = false; // 重置跳跃键
        }
    }
}

// 更新相机位置和方向
function updateCamera() {
    camera.position.copy(playerBody.position);
    camera.position.y += 1.7; // 眼睛高度
    
    // 更新相机旋转
    camera.rotation.order = 'YXZ';
    camera.rotation.y = game.player.rotation.y;
    camera.rotation.x = game.player.rotation.x;
}

// 指针锁定状态变化（桌面端）
if (!isTouchDevice) {
    document.addEventListener('pointerlockchange', () => {
        isMouseLocked = document.pointerLockElement === document.getElementById('gameCanvas');
        document.getElementById('crosshair').style.display = isMouseLocked ? 'block' : 'none';
        
        if (isMouseLocked) {
            console.log('指针已锁定 - 可以移动鼠标控制视角');
        } else {
            console.log('指针已解锁');
        }
    });
}

// 游戏主循环
let animationId = null;

function animate() {
    // 始终渲染场景，无论游戏是否运行
    renderer.render(scene, camera);
    
    // 如果游戏正在运行且未暂停，更新游戏逻辑
    if (game.isRunning && !game.isPaused) {
        const deltaTime = Math.min(clock.getDelta(), 0.1);
        
        // 更新物理世界
        if (world) {
            world.step(1/60, deltaTime, 3);
        }
        
        // 处理玩家输入
        handlePlayerInput(deltaTime);
        
        // 更新时间
        game.gameTime -= deltaTime;
        if (game.gameTime <= 0) {
            game.gameTime = 0;
            gameOver(false);
        }
        
        // 更新敌人
        updateEnemies(deltaTime);
        
        // 更新子弹
        updateBullets(deltaTime);
        
        // 更新拾取物
        updatePickups();
        
        // 更新相机位置
        updateCamera();
        
        // 更新UI
        updateUI();
    }
    
    // 继续下一帧
    animationId = requestAnimationFrame(animate);
}

// 停止游戏循环
function stopAnimation() {
    if (animationId) {
        cancelAnimationFrame(animationId);
        animationId = null;
    }
}

// 更新调试信息
function updateDebugInfo(message) {
    const debugElement = document.getElementById('debugInfo');
    if (debugElement) {
        debugElement.textContent = message;
    }
    console.log(message);
}

// 检查Three.js和Cannon.js是否加载
function checkLibraries() {
    if (!window.THREE) {
        throw new Error('Three.js 库未加载，请检查网络连接');
    }
    
    // 检查Cannon.js是否加载 - 支持不同的全局变量名
    let cannonLoaded = false;
    if (window.CANNON) {
        cannonLoaded = true;
        console.log('Cannon.js 已加载 (CANNON 变量)');
    } else if (window.CANNON_ES) {
        // 如果cannon-es使用不同的变量名
        window.CANNON = window.CANNON_ES;
        cannonLoaded = true;
        console.log('Cannon.js 已加载 (CANNON_ES 变量，已映射到 CANNON)');
    } else if (window.cannon) {
        window.CANNON = window.cannon;
        cannonLoaded = true;
        console.log('Cannon.js 已加载 (cannon 变量，已映射到 CANNON)');
    }
    
    if (!cannonLoaded) {
        // 尝试从其他常见位置查找
        console.warn('Cannon.js 未找到，检查 window 对象上的变量:', Object.keys(window).filter(k => k.toLowerCase().includes('cannon')));
        
        // 尝试动态加载备用CDN
        const fallbackCDN = 'https://unpkg.com/cannon-es@0.20.0/dist/cannon-es.min.js';
        console.log('尝试从备用CDN加载: ' + fallbackCDN);
        updateDebugInfo('Cannon.js 未加载，尝试备用CDN...');
        
        // 创建备用脚本
        const script = document.createElement('script');
        script.src = fallbackCDN;
        script.onload = function() {
            console.log('备用CDN加载成功，重新检查...');
            if (window.CANNON || window.CANNON_ES || window.cannon) {
                console.log('Cannon.js 已通过备用CDN加载成功');
                updateDebugInfo('Cannon.js 已通过备用CDN加载成功');
                
                // 尝试重新初始化游戏
                try {
                    // 检查是否可以初始化
                    if (!scene || !camera) {
                        console.log('备用CDN加载后重新尝试初始化...');
                        updateDebugInfo('重新初始化游戏...');
                        setTimeout(() => {
                            try {
                                init();
                                console.log('游戏重新初始化成功！');
                                updateDebugInfo('游戏重新初始化成功！点击"开始游戏"按钮开始');
                                
                                // 启用开始按钮
                                const startButton = document.getElementById('startButton');
                                if (startButton) {
                                    startButton.disabled = false;
                                    startButton.textContent = '开始游戏';
                                }
                            } catch (initError) {
                                console.error('重新初始化失败:', initError);
                                updateDebugInfo('重新初始化失败: ' + initError.message);
                            }
                        }, 500);
                    }
                } catch (error) {
                    console.error('备用CDN加载后处理失败:', error);
                }
            } else {
                console.error('备用CDN加载后仍未找到Cannon.js');
                updateDebugInfo('错误: Cannon.js 库未加载成功');
            }
        };
        script.onerror = function() {
            console.error('备用CDN加载失败');
            updateDebugInfo('错误: 无法加载Cannon.js物理引擎');
        };
        
        document.head.appendChild(script);
        
        // 不立即抛出错误，而是设置一个状态，允许用户稍后重试
        console.warn('Cannon.js 未加载，已启动异步加载，可能需要等待几秒');
        updateDebugInfo('Cannon.js 正在异步加载中...');
        
        // 返回false但不抛出错误，让初始化继续
        // 注意：这可能导致后续的物理世界创建失败，但我们会捕获这个错误
        return false;
    }
    
    console.log('Three.js 版本:', THREE.REVISION);
    console.log('Cannon.js 可用');
    
    // 检查WebGL支持
    if (!renderer || !renderer.capabilities) {
        const canvas = document.createElement('canvas');
        const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
        if (!gl) {
            throw new Error('您的浏览器不支持WebGL，请使用Chrome、Firefox或Safari等现代浏览器');
        }
    }
    
    return true;
}

// 初始化游戏
window.addEventListener('load', () => {
    console.log('页面加载完成，开始初始化游戏...');
    updateDebugInfo('页面加载完成，开始初始化...');
    
    try {
        // 检查库是否加载
        updateDebugInfo('检查Three.js和Cannon.js库...');
        const librariesLoaded = checkLibraries();
        
        // 检测是否为移动设备
        isTouchDevice = 'ontouchstart' in window || navigator.maxTouchPoints > 0;
        const deviceType = isTouchDevice ? '移动设备' : '桌面设备';
        console.log('设备检测: ', deviceType, {
            ontouchstart: 'ontouchstart' in window,
            maxTouchPoints: navigator.maxTouchPoints,
            userAgent: navigator.userAgent
        });
        updateDebugInfo(`设备类型: ${deviceType}`);
        
        // 如果是移动设备，确保移动控制按钮可见
        if (isTouchDevice) {
            const mobileControls = document.getElementById('mobileControls');
            if (mobileControls) {
                mobileControls.classList.add('mobile-only');
                mobileControls.style.display = 'none'; // 游戏开始前隐藏
                console.log('移动控制元素找到并设置为移动专用');
            }
        }
        
        // 初始化游戏
        updateDebugInfo('创建3D场景和物理世界...');
        init();
        
        // 根据库加载状态更新UI
        if (librariesLoaded) {
            console.log('游戏初始化成功！');
            updateDebugInfo('游戏初始化成功！点击"开始游戏"按钮开始');
            
            // 启用开始按钮
            const startButton = document.getElementById('startButton');
            if (startButton) {
                startButton.disabled = false;
                startButton.textContent = '开始游戏';
            }
        } else {
            // Cannon.js正在异步加载中
            console.log('游戏场景已创建，等待Cannon.js物理引擎加载...');
            updateDebugInfo('游戏场景已创建，物理引擎加载中...');
            
            // 禁用开始按钮，等待物理引擎加载完成
            const startButton = document.getElementById('startButton');
            if (startButton) {
                startButton.disabled = true;
                startButton.textContent = '等待物理引擎加载...';
            }
        }
        
    } catch (error) {
        console.error('游戏初始化失败:', error);
        const errorMessage = `游戏初始化失败: ${error.message}`;
        updateDebugInfo(errorMessage);
        alert(errorMessage);
        
        // 禁用开始按钮
        const startButton = document.getElementById('startButton');
        if (startButton) {
            startButton.disabled = true;
            startButton.textContent = '初始化失败，请刷新页面';
        }
    }
});

// 导出函数供HTML调用
window.startGame = startGame;
window.restartGame = restartGame;
window.showStartScreen = showStartScreen;
window.toggleFullscreen = toggleFullscreen;