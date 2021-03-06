(require :jaxon_jvrc "package://hrpsys_ros_bridge_jvrc/euslisp/jaxon_jvrc-interface.l")

(defun setup-robot (&key (robot 'jaxon_jvrc) (view t))
  ;; generate robot and object models
  (unless (boundp '*robot*)
    (progn
      (setq *robot* (funcall robot))
      (when view
        (objects (flatten
                  (list *robot*
                        (let (ret tmp (width 1500) (depth 1500) (height 1200))
                          (dotimes (i 3)
                            (dotimes (j 3)
                              (setq tmp (make-cube width depth height))
                              (send tmp :translate (float-vector (* i width) (* j depth) (/ height 2)))
                              (send tmp :set-color (float-vector (* 0.3 i) (- 1.0 (* 0.3 j)) (* 0.2 j)) 0.4)
                              (push tmp ret)))
                          ret)))))))
  (when view
    (send *irtviewer* :change-background #f(0.3 0.5 0.7))
    (send *irtviewer* :draw-objects))
  )

;; (warn "(reset-pose-to-touch-down)~%")
(defun reset-pose-to-touch-down
  (&key (offset (float-vector 0 0 0)))
  (let (ret)
    ;; reset pose
    (if (equal (send *robot* :name) "STARO")
        (send *robot* :torso :waist-p :max-angle 60))
    (send *irtviewer* :draw-objects)

    (send *robot* :reset-pose)
    (send *robot* :fix-leg-to-coords (make-coords))
    (if (equal (send *robot* :name) "STARO")
        (send *robot* :move-centroid-on-foot :both '(:rarm :larm :rleg :lleg)
              :target-centroid-pos (float-vector 30 0 0))
      (send *robot* :move-centroid-on-foot :both '(:rarm :larm :rleg :lleg)))
    (push (list :angle-vector (send *robot* :angle-vector)
                :time 5000)
          ret)
    (send *irtviewer* :draw-objects)
    ;; contact
    (let ((tc
           (list
            (make-coords :pos (v+ (send *robot* :rleg :end-coords :worldpos)
                                  (float-vector 400 -250 0)))
            (make-coords :pos (v+ (send *robot* :lleg :end-coords :worldpos)
                                  (float-vector 400 +250 0)))
            (send *robot* :rleg :end-coords :copy-worldcoords)
            (send *robot* :lleg :end-coords :copy-worldcoords)))
          (ll
           (list (send *robot* :get :rhand-contact-coords)
                 (send *robot* :get :lhand-contact-coords)
                 (send *robot* :rleg :end-coords)
                 (send *robot* :lleg :end-coords)
                 )))
      ;;(print (mapcar #'(lambda (l) (send *robot* :link-list (send l :parent))) ll))
      (send *robot*
            :fullbody-inverse-kinematics tc
            :move-target ll
            :link-list (mapcar #'(lambda (l) (send *robot* :link-list (send l :parent))) ll)
            :additional-weight-list (list (list (send *robot* :torso :waist-y :child-link) 0.0)
                                          (list (send *robot* :rarm :collar-y :child-link) 0.8)
                                          (list (send *robot* :larm :collar-y :child-link) 0.8)
                                          )
            :target-centroid-pos (apply #'midpoint 0.5 (send *robot* :legs :end-coords :worldpos))
            :min (float-vector -100 -100 -1000 -90 -90 -90)
            :max (float-vector +100 +100 +1000 +90 +90 +90)
            :root-link-virtual-joint-weight (float-vector 0.1 0.1 0.8 0.1 0.8 0.0)
            :debug-view :no-message)
      (send *robot* :fix-leg-to-coords (make-coords))
      (push (list :angle-vector (send *robot* :angle-vector)
                  :time 5000)
            ret))
    (send *irtviewer* :draw-objects)
    ;; touch down
    (let* ((tcl (mapcar #'(lambda (x) (send *robot* x :end-coords :copy-worldcoords))
                        (list :rarm :larm :rleg :lleg)))
           (tcp (scale (/ 1.0 4) (reduce #'v+ (send-all tcl :worldpos))))
           (target-z-pos 1000))
      (send *robot* :legs  :knee-p   :joint-angle 80)
      (send *robot* :legs  :crotch-p :joint-angle -80)
      (send *robot* :torso :waist-p  :joint-angle 30)
      (send *robot* :fix-leg-to-coords (make-coords))

      (with-move-target-link-list
       (mt ll *robot* '(:rarm :larm :rleg :lleg))
       (send *robot*
             :fullbody-inverse-kinematics tcl
             :move-target mt
             :link-list ll
             :additional-weight-list (list (list (send *robot* :torso :waist-y :child-link) 0.0))
             :root-link-virtual-joint-weight (float-vector 0.1 0.1 0.5 0.1 0.5 0.0)
             :target-centroid-pos tcp))
      (push (list :angle-vector (send *robot* :angle-vector)
                  :time 5000)
            ret)
      (send *irtviewer* :draw-objects))
    (reverse ret)))

(warn "(init)~%")
(defun init ()
  (setup-robot :robot 'jaxon_jvrc-init)
  (send *ri* :set-auto-balancer-param :transition-time 5)
  (send *ri* :start-auto-balancer)
  (send *ri* :start-grasp)
  (send *ri* :start-impedance :arms)
  (dolist (l (list :rarm :larm)) (send *ri* :set-impedance-controller-param l :k-p 1000)))

(warn "(move-to-init-pose :type :biped)~%")
(defun move-to-init-pose (&key (type :biped))
  (case type
    (:biped
     (let ((avs (reset-pose-to-touch-down)))
       (send *ri* :angle-vector (cadr (memq :angle-vector (elt avs 0))) 200)
       (send *ri* :wait-interpolation)
       (send *ri* :angle-vector (cadr (memq :angle-vector (elt avs 1))) 800)
       (send *ri* :wait-interpolation))
     (send *ri* :start-st)
     (send *robot* :angle-vector (send *ri* :state :potentio-vector))
     (send *robot* :fix-leg-to-coords (make-coords))
     (send *robot* :rarm :angle-vector #f(+80.0 0.0 -90.0 -90.0 -120.0 -90.0 0.0 -80.0))
     (send *robot* :larm :angle-vector #f(-80.0 0.0 +90.0 +90.0 -120.0 +90.0 0.0 -80.0))
     (send *robot* :move-centroid-on-foot :both '(:rleg :lleg))
     (send *ri* :angle-vector (send *robot* :angle-vector) 500)
     (send *ri* :wait-interpolation))
    (:quadruped
     (dolist (avs (reset-pose-to-touch-down))
       (send *ri* :angle-vector (cadr (memq :angle-vector avs)))
       (send *ri* :wait-interpolation))
     (send *ri* :stop-auto-balancer))
    ))

(defun go-pos-quad (&key (x 0) (y 0) (th 0) (type :crawl) (debug-view nil) (dt 0.1)
                         (default-step-time 1.0) (default-step-height 50))
  (let* ((fsl (send *robot* :go-pos-quadruped-params->footstep-list x y th :type type))
         (ik-args
          (list :min (float-vector -1e5 -1e5 -1e5 -180 -180 -180)
                :max (float-vector +1e5 +1e5 +1e5 +180 +180 +180)
                :absolute-p t
                :debug-view debug-view
                :cog-null-space nil
                :additional-weight-list (list (list (send *robot* :torso :waist-y :child-link) 0.0))
                :root-link-virtual-joint-weight (float-vector 0.5 0.5 0.5 0.0 0.0 0.0)
                :cog-gain 5.0 :centroid-thre 50
                :init nil)))
    (send *robot* :calc-walk-pattern-from-footstep-list
          fsl
          :debug-view :no-message
          :all-limbs '(:rleg :lleg :rarm :larm)
          :init-pose-function #'(lambda () nil)
          :solve-angle-vector-args ik-args
          :default-step-height default-step-height
          :default-step-time default-step-time
          :dt dt
          )
    )
  )

(defun go-pos-quad-real (&key (x 0) (y 0) (th 0) (type :trot) (dt 0.1) ((:scale scl) 1)
                              (default-step-height 50) (default-step-time 1.0))
  ;; (send *robot* :angle-vector (send *ri* :state :potentio-vector))
  ;; (send *robot* :fix-leg-to-coords (make-coords))
  (let* ((walk-pattern (go-pos-quad :x x :y y :th th :type type :dt dt
                                    :default-step-height default-step-height
                                    :default-step-time default-step-time))
         (tms (make-list (length walk-pattern) :initial-element (* dt 1e3))))
    (send *ri* :angle-vector (cadr (memq :angle-vector (car walk-pattern)))
          (* scl 100))
    (send *ri* :wait-interpolation)
    (send *ri* :angle-vector-sequence
          (mapcar #'(lambda (x) (cadr (memq :angle-vector x))) walk-pattern) tms)
    (send *ri* :wait-interpolation)
    ))

(defun auto-mode ()
  (format t "start-auto-mode: ~A~%" (unix::asctime (unix::localtime)))
  (init)
  (format t "init done: ~A~%" (unix::asctime (unix::localtime)))
  (move-to-init-pose)
  (format t "move-to-init-pose done: ~A~%" (unix::asctime (unix::localtime)))
  (send *ri* :set-gait-generator-param
        :default-step-time 1.0
        :stride-parameter (float-vector 0.15 0.05 30.0 0.05)
        :optional-go-pos-finalize-footstep-num 0)
  (progn
    (send *ri* :go-pos (+ (* 1.5 1) 0.3) 0 0)
    (send *ri* :go-pos 0 0 90)
    (send *ri* :go-pos (+ (* 1.5 3) 0.3) 0 0)
    (send *ri* :go-pos 0 0 -90)
    (send *ri* :go-pos (+ (* 1.5 4) 0.3) 0 0)
    (send *ri* :go-pos 0 0 -90)
    (send *ri* :go-pos (+ (* 1.5 1) 0.3) 0 0)
    (send *ri* :go-pos 0 0 90)
    (send *ri* :go-pos (+ (* 1.5 1) 0.3) 0 0)
    (send *ri* :go-pos 0 0 -90)
    (send *ri* :go-pos (+ (* 1.5 2) 0.3) 0 0)
    (send *ri* :go-pos 0 0 90)
    (send *ri* :go-pos (+ (* 1.5 2) 0.3) 0 0)
    )
  (format t "finish: ~A~%" (unix::asctime (unix::localtime)))
  )
