#ENV["CUDA_VISIBLE_DEVICES"] = "0,1,2,3,4,5,6,7"
#using Revise
using ADSeismic
using ADCME
using PyPlot
using MAT
using Optim
using Random
using DelimitedFiles
using Dates
matplotlib.use("Agg")
close("all")

gpu = has_gpu() ? true : false

data_dir = "data/acoustic"
method = "FWI"

figure_dir = string("figure/",method,"/marmousi/")
result_dir = string("result/",method,"/marmousi/")
loss_file = joinpath(result_dir, "loss_$(Dates.now()).txt")

check_path(dir) = !ispath(data_dir) ? mkpath(dir) : nothing
check_path(figure_dir)
check_path(result_dir)
check_path(model_dir)

################### Inversion using Automatic Differentiation #####################
reset_default_graph()
model_name = "models/marmousi2-model-smooth-large.mat"
# model_name = "models/BP-model-smooth.mat"

## load model setting
params = load_params(model_name, vp_ref=3e3, PropagatorKernel=1)
src = load_acoustic_source(model_name)
rcv = load_acoustic_receiver(model_name)
vp0 = matread(model_name)["vp"]
mask = matread(model_name)["mask"]

vp = Variable(vp0)
vp = mask .* vp + (1.0.-mask) .* vp0

## assemble acoustic propagator model
model = x->AcousticPropagatorSolver(params, x, vp^2)

## load data
std_noise = 0
Random.seed!(1234);
Rs = Array{Array{Float64,2}}(undef, length(src))
for i = 1:length(src)
    Rs[i] = readdlm(joinpath(data_dir, "marmousi-r$i.txt"))
    # Rs[i] = readdlm(joinpath(data_dir, "BP-r$i.txt"))
    Rs[i] .+= ( randn(size(Rs[i])) .+ mean(Rs[i]) ) .* std(Rs[i]) .* std_noise
end

## calculate loss
if gpu
  losses, grads = compute_loss_and_grads_GPU(model, src, rcv, Rs, vp)
  grad = sum(grads)
  loss = sum(losses)
else
  [SimulatedObservation!(model(src[i]), rcv[i]) for i = 1:length(src)]
  loss = sum([sum((rcv[i].rcvv-Rs[i])^2) for i = 1:length(rcv)]) 
  grad = gradients(loss)
end

global_step = tf.Variable(0, trainable=false)
max_iter = 50000
lr_decayed = tf.train.cosine_decay(1.0, global_step, max_iter)
opt = AdamOptimizer(lr_decayed).minimize(loss, global_step=global_step, colocate_gradients_with_ops=true)

sess = Session(); init(sess)
loss0 = run(sess, loss)
@info "Initial loss: ", loss0

## run inversion
fp = open(loss_file, "w")
write(fp, "0,$loss0\n")
function callback(vs, iter, loss)
  if iter%10==0

    # x = Array(reshape(vs[1:(params.NY+2)*(params.NX+2)], params.NY+2, params.NX+2))
    x = run(sess, vp)'
    clf()
    pcolormesh([0:params.NX+1;]*params.DELTAX/1e3,[0:params.NY+1;]*params.DELTAY/1e3,  x)
    axis("scaled")
    colorbar(shrink=0.4)
    xlabel("x (km)")
    ylabel("z (km)")
    gca().invert_yaxis()
    title("Iteration = $iter")
    savefig(joinpath(figure_dir, "inv_$(lpad(iter,5,"0")).png"), bbox_inches="tight")
    writedlm(joinpath(result_dir, "inv_$(lpad(iter,5,"0")).txt"), x)
  end
  write(fp, "$iter,$loss\n")
  flush(fp)
end


## BFGS
Optimize!(sess, loss, 10000, vars=[vp], grads=grad,  callback=callback)

## Adam
# time = 0
# for iter = 0:max_iter
#   t = @elapsed  _, ls, lr = run(sess, [opt, loss, lr_decayed])
#   callback(nothing, iter, ls)
#   println("   $iter\t$ls\t$lr\t$t")
# end

close(fp)
